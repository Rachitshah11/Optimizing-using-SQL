
/*  Queries for Inventory Turnover & Efficiency Analysis  */



-- Query 1: Inventory Turnover Ratio by Product and Store (Corrected)

-- Declare and set a variable for the most recent date for efficiency
DECLARE @MaxDate DATE;
SET @MaxDate = (SELECT MAX(Date) FROM Dim_Date);

WITH Inventory_Turnover AS (
    SELECT
        f.Product_SK,
        f.Store_SK,
        SUM(f.Units_Sold) AS Total_Units_Sold,
        AVG(CAST(f.Inventory_Level AS FLOAT)) AS Avg_Inventory, 
        CASE
            WHEN AVG(f.Inventory_Level) > 0
            THEN SUM(f.Units_Sold) * 1.0 / AVG(f.Inventory_Level)
            ELSE 0
        END AS Turnover_Ratio
    FROM Fact_Inventory_Sales f
    JOIN Dim_Date dd ON f.Date_SK = dd.Date_SK
    
    WHERE dd.Date >= DATEADD(day, -90, @MaxDate)
    GROUP BY f.Product_SK, f.Store_SK
)
SELECT
    dp.Product_ID,
    dp.Category,
    ds.Store_ID,
    ds.Region,
    ROUND(it.Total_Units_Sold, 0) AS Units_Sold_90_Days,
    ROUND(it.Avg_Inventory, 0) AS Avg_Inventory_Level,
    ROUND(it.Turnover_Ratio, 2) AS Turnover_Ratio,
    CASE
        WHEN it.Turnover_Ratio > 2 THEN 'FAST MOVING'
        WHEN it.Turnover_Ratio > 0.5 THEN 'MODERATE MOVING'
        WHEN it.Turnover_Ratio > 0 THEN 'SLOW MOVING'
        ELSE 'NOT MOVING'
    END AS Movement_Category,
    CASE
        WHEN it.Turnover_Ratio > 2 THEN 'INCREASE STOCK'
        WHEN it.Turnover_Ratio < 0.2 AND it.Turnover_Ratio > 0 THEN 'REDUCE STOCK'
        ELSE 'MAINTAIN CURRENT LEVELS'
    END AS Recommendation
FROM Inventory_Turnover it
JOIN Dim_Product dp ON it.Product_SK = dp.Product_SK
JOIN Dim_Store ds ON it.Store_SK = ds.Store_SK
WHERE it.Avg_Inventory > 0 
ORDER BY it.Turnover_Ratio DESC;


--******************************************************************************--

/* Query 2: Average Days of Inventory on Hand
This query calculates the average Days of Inventory on Hand.
A lower number indicates more efficient inventory management.
Days on Hand = (Average Inventory / Total Units Sold) * Number of Days */
WITH
Period_Data AS ( 
SELECT 
	Product_SK, 
	Store_SK, 
	AVG(CAST(Inventory_Level AS DECIMAL(10,2))) as Avg_Stock, 
	SUM(Units_Sold) as Total_Sold, 
	COUNT(DISTINCT Date_SK) as Num_Days 
	FROM Fact_Inventory_Sales 
	GROUP BY Product_SK, Store_SK
)
SELECT s.Region, p.Category, -- Calculate overall weighted average days on hand 
SUM(pd.Avg_Stock * pd.Num_Days) / NULLIF(SUM(pd.Total_Sold), 0) AS Avg_Days_of_Inventory_on_Hand
FROM Period_Data pd
JOIN Dim_Product p 
ON pd.Product_SK = p.Product_SK
JOIN Dim_Store s 
ON pd.Store_SK = s.Store_SK
WHERE pd.Total_Sold > 0
GROUP BY s.Region, p.Category
ORDER BY Avg_Days_of_Inventory_on_Hand ASC;


--***************************************************************************--

/* Query 3 : Working Capital Analysis in Inventory
This query analyzes working capital efficiency by showing the monetary value
of inventory held in different categories and regions. */

--CTE : To Get the most recent inventory value for each product at each store 
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
	SUM(civ.Inventory_Value) AS Working_Capital_In_Inventory
FROM CurrentInventoryValue civ
JOIN Dim_Store ds 
ON civ.Store_SK = ds.Store_SK
JOIN Dim_Product dp 
ON civ.Product_SK = dp.Product_SK
WHERE civ.rn = 1 AND civ.Inventory_Value > 0
GROUP BY ds.Region, dp.Category
ORDER BY Working_Capital_In_Inventory DESC;


--*****************************************************************--

/* Query 4: Historical Inventory Value Trend
   This query tracks the total value of all inventory at the end of each month. */

--CTE : Identify the last record of each month for each product/store  
WITH MonthEndStock AS ( 
SELECT 
	fis.Inventory_Level, 
	fis.Price, 
	d.Year, 
	d.Month, 
	ROW_NUMBER() OVER(PARTITION BY fis.Product_SK, fis.Store_SK, d.Year, d.Month 
	ORDER BY d.Date DESC) AS rn 
FROM Fact_Inventory_Sales fis 
JOIN Dim_Date d 
ON fis.Date_SK = d.Date_SK
)
SELECT 
	mes.Year, 
	mes.Month, 
	SUM(CAST(mes.Inventory_Level AS BIGINT) * mes.Price) AS Total_Inventory_Value
FROM MonthEndStock mes
WHERE mes.rn = 1 
GROUP BY mes.Year, mes.Month
ORDER BY mes.Year, mes.Month;


--*********************************************************************************--

/* Query 5: Aggregated Inventory Turnover Ratio
This query calculates the inventory turnover ratio. A higher ratio is generally better.
Ratio = Total Units Sold / Average Inventory Level  */
WITH InventoryMetrics AS ( 
SELECT 
	Store_SK, 
	Product_SK, 
	SUM(Units_Sold) AS Total_Units_Sold, 
	AVG(CAST(Inventory_Level AS DECIMAL(10, 2))) AS Avg_Inventory_Level 
	FROM Fact_Inventory_Sales 
	GROUP BY Store_SK, Product_SK
)
SELECT 
	ds.Region, 
	dp.Category, 
	ROUND(SUM(im.Total_Units_Sold) / NULLIF(SUM(im.Avg_Inventory_Level), 0),2) AS Inventory_Turnover_Ratio
FROM InventoryMetrics im
JOIN Dim_Store ds 
ON im.Store_SK = ds.Store_SK
JOIN Dim_Product dp 
ON im.Product_SK = dp.Product_SK
WHERE im.Avg_Inventory_Level > 0
GROUP BY ds.Region, dp.Category
ORDER BY Inventory_Turnover_Ratio DESC;
