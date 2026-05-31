
-- Query: Dynamic Reorder Point Calculation Based on Historical Sales

-- Declare and set a variable for the most recent date
DECLARE @MaxDate DATE;
SET @MaxDate = (SELECT MAX(Date) FROM Dim_Date);

WITH Sales_Stats AS (
    SELECT
        f.Product_SK,
        f.Store_SK,
        AVG(CAST(f.Units_Sold AS FLOAT)) AS Avg_Daily_Sales, -- CAST to float for accurate AVG
        STDEV(f.Units_Sold) AS Sales_Std_Dev, 
        MAX(f.Units_Sold) AS Max_Daily_Sales
    FROM Fact_Inventory_Sales f
    JOIN Dim_Date dd ON f.Date_SK = dd.Date_SK
    WHERE dd.Date >= DATEADD(day, -90, @MaxDate)
    GROUP BY f.Product_SK, f.Store_SK
),
Reorder_Calculation AS (
    SELECT
        ss.*,
        dp.Product_ID,
        dp.Category,
        ds.Store_ID,
        ds.Region,
        -- Lead time assumption: 7 days
        -- Safety stock: 2 standard deviations from the mean
        CEILING(ss.Avg_Daily_Sales * 7 + 2 * COALESCE(ss.Sales_Std_Dev, 0)) AS Suggested_Reorder_Point,
        CEILING(ss.Avg_Daily_Sales * 14) AS Suggested_Max_Stock
    FROM Sales_Stats ss
    JOIN Dim_Product dp ON ss.Product_SK = dp.Product_SK
    JOIN Dim_Store ds ON ss.Store_SK = ds.Store_SK
)
SELECT
    Product_ID,
    Category,
    Store_ID,
    Region,
    ROUND(Avg_Daily_Sales, 2) AS Avg_Daily_Sales,
    Suggested_Reorder_Point,
    Suggested_Max_Stock,
    CASE
        WHEN Avg_Daily_Sales > 10 THEN 'HIGH VELOCITY'
        WHEN Avg_Daily_Sales > 3 THEN 'MEDIUM VELOCITY'
        ELSE 'LOW VELOCITY'
    END AS Product_Velocity
FROM Reorder_Calculation
WHERE Avg_Daily_Sales > 0
ORDER BY Avg_Daily_Sales DESC;