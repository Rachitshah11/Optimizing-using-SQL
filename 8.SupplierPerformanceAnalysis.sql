
-- Query : Supplier Performance Scorecard
-- Assuming supplier information is embedded in product data or a separate table.
-- This query uses product category as a proxy for supplier performance.

WITH Supplier_Metrics AS (
    SELECT
        dp.Category,
        COUNT(DISTINCT dp.Product_ID) AS Products_Supplied,
        SUM(f.Units_Sold) AS Total_Units_Sold,
        SUM(f.Units_Sold * f.Price) AS Total_Revenue_Generated,
        AVG(f.Price) AS Avg_Product_Price,
        -- Stockout frequency by supplier products
        SUM(CASE WHEN f.Inventory_Level = 0 THEN 1 ELSE 0 END) AS Stockout_Instances,
        COUNT(*) AS Total_Records, 
        ROUND(SUM(CASE WHEN f.Inventory_Level = 0 THEN 1 ELSE 0 END) * 100.0 / COUNT(*), 2) AS Stockout_Rate
    FROM
        Fact_Inventory_Sales AS f
    JOIN
        Dim_Product AS dp ON f.Product_SK = dp.Product_SK
    JOIN
        Dim_Date AS dd ON f.Date_SK = dd.Date_SK
    WHERE
        dd.Date >= DATEADD(day, -90, (SELECT MAX(Date) FROM Dim_Date))
    GROUP BY
        dp.Category
)
SELECT
    Category AS Supplier_Category,
    Products_Supplied,
    Total_Units_Sold,
    ROUND(Total_Revenue_Generated, 2) AS Revenue_Generated,
    ROUND(Avg_Product_Price, 2) AS Avg_Price_Point,
    Stockout_Rate AS Stockout_Rate_Percent,
    CASE
        WHEN Stockout_Rate < 2 THEN 'EXCELLENT'
        WHEN Stockout_Rate < 5 THEN 'GOOD'
        WHEN Stockout_Rate < 10 THEN 'NEEDS IMPROVEMENT'
        ELSE 'POOR'
    END AS Supplier_Rating,
    CASE
        WHEN Stockout_Rate > 10 THEN 'FIND ALTERNATIVE SUPPLIERS'
        WHEN Stockout_Rate > 5 THEN 'NEGOTIATE BETTER TERMS'
        ELSE 'MAINTAIN RELATIONSHIP'
    END AS Action_Recommendation
FROM
    Supplier_Metrics
ORDER BY
    Revenue_Generated DESC;