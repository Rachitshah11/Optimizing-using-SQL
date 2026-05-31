

-- Query 13: Comprehensive Action Plan 

-- Declare and set a variable for the most recent date for efficiency and clarity
DECLARE @MaxDate DATE;
SET @MaxDate = (SELECT MAX(Date) FROM Dim_Date);

WITH Action_Items AS (
    SELECT
        f.Product_SK,
        f.Store_SK,
        AVG(CAST(f.Inventory_Level AS FLOAT)) AS Current_Avg_Inventory,
        SUM(f.Units_Sold) AS Recent_Sales,
        AVG(CAST(f.Units_Sold AS FLOAT)) AS Avg_Daily_Sales,
        CASE
            WHEN AVG(f.Inventory_Level) = 0 AND SUM(f.Units_Sold) > 0 THEN 'URGENT_RESTOCK'
            -- If avg inventory is less than 3 days of sales, increase stock
            WHEN AVG(f.Inventory_Level) < AVG(CAST(f.Units_Sold AS FLOAT)) * 3.0 THEN 'INCREASE_STOCK'
            -- If avg inventory is more than 10 days of sales AND sales are very low, reduce stock
            WHEN AVG(f.Inventory_Level) > AVG(CAST(f.Units_Sold AS FLOAT)) * 10.0 AND SUM(f.Units_Sold) < 5 THEN 'REDUCE_STOCK'
            -- If it hasn't sold at all and inventory is high, consider discontinuing
            WHEN SUM(f.Units_Sold) = 0 AND AVG(f.Inventory_Level) > 20 THEN 'CONSIDER_DISCONTINUE'
            ELSE 'MAINTAIN'
        END AS Action_Required
    FROM Fact_Inventory_Sales f
    JOIN Dim_Date dd ON f.Date_SK = dd.Date_SK
    WHERE dd.Date >= DATEADD(day, -30, @MaxDate)
    GROUP BY f.Product_SK, f.Store_SK
)
SELECT
    ai.Action_Required,
    dp.Category,
    ds.Region,
    COUNT(*) AS Number_of_Items,
    SUM(ai.Current_Avg_Inventory) AS Total_Current_Inventory,
    SUM(ai.Recent_Sales) AS Total_Recent_Sales,
    CASE ai.Action_Required
        WHEN 'URGENT_RESTOCK' THEN 'Order immediately to prevent lost sales'
        WHEN 'INCREASE_STOCK' THEN 'Increase inventory levels to prevent stockouts'
        WHEN 'REDUCE_STOCK' THEN 'Liquidate or transfer excess stock'
        WHEN 'CONSIDER_DISCONTINUE' THEN 'Evaluate product viability for this location'
        ELSE 'Current stock levels are appropriate'
    END AS Recommendation
FROM Action_Items ai
JOIN Dim_Product dp ON ai.Product_SK = dp.Product_SK
JOIN Dim_Store ds ON ai.Store_SK = ds.Store_SK
GROUP BY ai.Action_Required, dp.Category, ds.Region
ORDER BY
    CASE ai.Action_Required
        WHEN 'URGENT_RESTOCK' THEN 1
        WHEN 'INCREASE_STOCK' THEN 2
        WHEN 'REDUCE_STOCK' THEN 3
        WHEN 'CONSIDER_DISCONTINUE' THEN 4
        ELSE 5
    END,
    Number_of_Items DESC;