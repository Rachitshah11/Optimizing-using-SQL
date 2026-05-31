/*********************Queries for Stock Level Calculataions******************/

--Query 1: Current Stock Levels Across All Locations
SELECT
ds.Store_ID,
ds.Region,
dp.Product_ID,
dp.Category,
f.Inventory_Level AS Current_Stock,
CASE
WHEN f.Inventory_Level = 0 THEN 'OUT OF STOCK'
WHEN f.Inventory_Level <= 10 THEN 'CRITICAL LOW'
WHEN f.Inventory_Level <= 50 THEN 'LOW STOCK'
ELSE 'ADEQUATE'
END AS Stock_Status
FROM Fact_Inventory_Sales f
JOIN Dim_Store ds ON f.Store_SK = ds.Store_SK
JOIN Dim_Product dp ON f.Product_SK = dp.Product_SK
JOIN Dim_Date dd ON f.Date_SK = dd.Date_SK
WHERE dd.Date = (SELECT MAX(Date) FROM Dim_Date) -- Latest date only
ORDER BY ds.Region, dp.Category, f.Inventory_Level;

--**************************************************************************--

-- Query C2: Stock Levels by Region and Category
SELECT
ds.Region,
dp.Category,
COUNT(*) AS Total_SKUs,
SUM(f.Inventory_Level) AS Total_Stock_Units,
AVG(f.Inventory_Level) AS Avg_Stock_Per_SKU,
MIN(f.Inventory_Level) AS Min_Stock,
MAX(f.Inventory_Level) AS Max_Stock
FROM Fact_Inventory_Sales f
JOIN Dim_Store ds ON f.Store_SK = ds.Store_SK
JOIN Dim_Product dp ON f.Product_SK = dp.Product_SK
JOIN Dim_Date dd ON f.Date_SK = dd.Date_SK
WHERE dd.Date = (SELECT MAX(Date) FROM Dim_Date)
GROUP BY ds.Region, dp.Category
ORDER BY ds.Region, Total_Stock_Units DESC;


--***************************************************************--
/*Query 3:This query retrieves the latest inventory level for each product at each store
-- and aggregates it by location and product category.    */
WITH LatestInventory AS ( -- First, identify the most recent record for each product at each store 
SELECT 
	fis.Store_SK, 
	fis.Product_SK, 
	fis.Inventory_Level, 
	ROW_NUMBER() OVER(PARTITION BY fis.Store_SK, fis.Product_SK 
	ORDER BY d.Date DESC) as rn 
FROM Fact_Inventory_Sales fis 
JOIN Dim_Date d 
ON fis.Date_SK = d.Date_SK
)
SELECT 
	ds.Region, 
	dp.Category, 
	ds.Store_ID, 
	dp.Product_ID, 
	li.Inventory_Level AS Current_Stock_Level
FROM LatestInventory li
JOIN Dim_Store ds 
ON li.Store_SK = ds.Store_SK
JOIN Dim_Product dp 
ON li.Product_SK = dp.Product_SK
WHERE li.rn = 1 -- Filter for only the most recent inventory record
ORDER BY ds.Region, dp.Category, Current_Stock_Level DESC;


--************************************************************************--

/* Query 20 : Low days of supply alert
This query identifies products with a low number of days of supply remaining.
Days of Supply = Current Inventory / Average Daily Sales */
WITH
SalesVelocity AS ( -- Calculate average daily sales for each product 
SELECT 
	Product_SK, 
	AVG(CAST(Units_Sold AS DECIMAL(10, 2))) AS Avg_Daily_Sales 
	FROM Fact_Inventory_Sales 
	WHERE Units_Sold > 0 
	GROUP BY Product_SK
),
CurrentStock AS ( -- Get the most recent inventory level for each product 
SELECT
	Product_SK, 
	Store_SK, 
	Inventory_Level 
	FROM ( SELECT 
							fis.Product_SK, 
							fis.Store_SK, 
							fis.Inventory_Level, 
							ROW_NUMBER() OVER(PARTITION BY fis.Product_SK, fis.Store_SK 
							ORDER BY d.Date DESC) as rn 
							FROM Fact_Inventory_Sales fis 
							JOIN Dim_Date d ON fis.Date_SK = d.Date_SK ) 
							AS LatestStock WHERE rn = 1
)
SELECT 
	ds.Region, 
	dp.Category, 
	dp.Product_ID, 
	cs.Inventory_Level, 
	sv.Avg_Daily_Sales, -- Calculate Days of Supply, handling cases where there are no sales 
	CASE WHEN sv.Avg_Daily_Sales > 0 THEN cs.Inventory_Level / sv.Avg_Daily_Sales ELSE 9999 -- Assign a high number if there are no sales 
	END AS Days_of_Supply
FROM CurrentStock cs
JOIN SalesVelocity sv ON cs.Product_SK = sv.Product_SK
JOIN Dim_Product dp ON cs.Product_SK = dp.Product_SK
JOIN Dim_Store ds ON cs.Store_SK = ds.Store_SK
WHERE cs.Inventory_Level > 0 AND (cs.Inventory_Level / sv.Avg_Daily_Sales) < 7 -- Alert threshold: less than 7 days of supply
ORDER BY Days_of_Supply ASC;


--***************************************************************************************--
/* Query 5 :
This query calculates the total value of current inventory, grouped by region and category. */
WITH CurrentInventoryValue AS ( 
SELECT 
	fis.Store_SK, 
	fis.Product_SK, 
	(fis.Inventory_Level * fis.Price) AS Inventory_Value, 
	ROW_NUMBER() OVER(PARTITION BY fis.Store_SK, fis.Product_SK 
	ORDER BY d.Date DESC) as rn 
FROM Fact_Inventory_Sales fis 
JOIN Dim_Date d 
ON fis.Date_SK = d.Date_SK
)
SELECT 
	ds.Region, 
	dp.Category, 
	SUM(civ.Inventory_Value) AS Total_Inventory_Value
FROM CurrentInventoryValue civ
JOIN Dim_Store ds ON civ.Store_SK = ds.Store_SK
JOIN Dim_Product dp ON civ.Product_SK = dp.Product_SK
WHERE civ.rn = 1 AND civ.Inventory_Value > 0
GROUP BY ds.Region, dp.Category
ORDER BY Total_Inventory_Value DESC;


--------***************************************************************--


/* Query 6: Obsolete Stock Detection
-- This query detects obsolete stock by finding products with inventory
-- that have not sold in a long time (e.g., 180 days).   */
WITH LastSaleDate AS ( 
SELECT 
	Product_SK, 
	MAX(d.Date) as Last_Sale_Date 
	FROM Fact_Inventory_Sales fis 
	JOIN Dim_Date d 
	ON fis.Date_SK = d.Date_SK 
	WHERE fis.Units_Sold > 0 
	GROUP BY Product_SK
),
CurrentStock AS ( 
SELECT 
	Product_SK, 
	SUM(Inventory_Level * Price) as Obsolete_Value 
	FROM ( SELECT 
						fis.Product_SK, 
						fis.Inventory_Level, 
						fis.Price, 
						ROW_NUMBER() OVER(PARTITION BY fis.Product_SK, fis.Store_SK 
						ORDER BY d.Date DESC) as rn 
				FROM Fact_Inventory_Sales fis 
				JOIN Dim_Date d 
				ON fis.Date_SK = d.Date_SK ) 
				AS LatestStock WHERE rn = 1 
				GROUP BY Product_SK
)
SELECT 
	p.Product_ID, 
	p.Category, 
	lsd.Last_Sale_Date, 
	cs.Obsolete_Value, 
	DATEDIFF(day, lsd.Last_Sale_Date, GETDATE()) AS Days_Since_Last_Sale
FROM Dim_Product p
JOIN CurrentStock cs 
ON p.Product_SK = cs.Product_SK
LEFT JOIN LastSaleDate lsd 
ON p.Product_SK = lsd.Product_SK
WHERE cs.Obsolete_Value > 0 
			AND DATEDIFF(day, COALESCE(lsd.Last_Sale_Date, '1900-01-01'), GETDATE()) > 180
ORDER BY cs.Obsolete_Value DESC;