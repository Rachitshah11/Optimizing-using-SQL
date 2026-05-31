
/* Queries for Advanced Analytics */

-- Query1 : ABC Classification for Inventory Manangement
IF OBJECT_ID('tempdb..#ABC_Data') IS NOT NULL
    DROP TABLE #ABC_Data;

WITH Product_Revenue AS (
    SELECT
        f.Product_SK,
        SUM(f.Units_Sold * f.Price) AS Total_Revenue,
        SUM(f.Units_Sold) AS Total_Units_Sold,
        AVG(f.Inventory_Level) AS Avg_Inventory_Level
    FROM Fact_Inventory_Sales f
    JOIN Dim_Date dd ON f.Date_SK = dd.Date_SK
    WHERE dd.Date >= DATEADD(day, -90, (SELECT MAX(Date) FROM Dim_Date))
    AND f.Units_Sold > 0
    GROUP BY f.Product_SK
),
Revenue_Ranking AS (
    SELECT
        *,
        ROW_NUMBER() OVER (ORDER BY Total_Revenue DESC) as Revenue_Rank,
        COUNT(*) OVER () as Total_Products,
        SUM(Total_Revenue) OVER () as Grand_Total_Revenue,
        SUM(Total_Revenue) OVER (ORDER BY Total_Revenue DESC) as Running_Revenue_Total
    FROM Product_Revenue
),
ABC_Classification AS (
    SELECT
        *,
        (Running_Revenue_Total / Grand_Total_Revenue * 100) as Revenue_Cumulative_Percent,
        CASE
            WHEN (Running_Revenue_Total / Grand_Total_Revenue * 100) <= 80 THEN 'A'
            WHEN (Running_Revenue_Total / Grand_Total_Revenue * 100) <= 95 THEN 'B'
            ELSE 'C'
        END as ABC_Class
    FROM Revenue_Ranking
)
-- insert the results into a temporary table instead of just selecting them
SELECT *
INTO #ABC_Data
FROM ABC_Classification;

--- RUN BOTH QUERIES USING THE TEMP TABLE ---

-- Run the detailed product report from the temporary table
SELECT
    dp.Product_ID,
    dp.Category,
    ac.ABC_Class,
    ROUND(ac.Total_Revenue, 2) AS Revenue_90_Days,
    ac.Total_Units_Sold,
    ROUND(ac.Avg_Inventory_Level, 0) AS Avg_Inventory,
    ROUND(ac.Revenue_Cumulative_Percent, 2) AS Cumulative_Revenue_Percent,
    CASE ac.ABC_Class
        WHEN 'A' THEN 'TIGHT CONTROL - Daily monitoring, safety stock'
        WHEN 'B' THEN 'MODERATE CONTROL - Weekly monitoring'
        WHEN 'C' THEN 'LOOSE CONTROL - Monthly review, minimize stock'
    END AS Management_Strategy
FROM #ABC_Data ac
JOIN Dim_Product dp ON ac.Product_SK = dp.Product_SK
ORDER BY ac.Total_Revenue DESC;


-- Step 3: Run the summary report from the temporary table
SELECT
    ABC_Class,
    COUNT(*) AS Number_of_Products,
    ROUND(COUNT(*) * 100.0 / MAX(Total_Products), 2) AS Percent_of_Products,
    ROUND(SUM(Total_Revenue), 2) AS Total_Revenue,
    ROUND(SUM(Total_Revenue) * 100.0 / MAX(Grand_Total_Revenue), 2) AS Percent_of_Revenue
FROM #ABC_Data
GROUP BY ABC_Class
ORDER BY ABC_Class;


--*****************************************************************************--

-- Query 2: Product Affinity Analysis (Simplified Market Basket)
WITH Daily_Store_Sales AS (
    SELECT
        f.Date_SK,
        f.Store_SK,
        f.Product_SK,
        SUM(f.Units_Sold) as Daily_Units_Sold
    FROM Fact_Inventory_Sales f
    WHERE f.Units_Sold > 0
    GROUP BY f.Date_SK, f.Store_SK, f.Product_SK
),
Product_Pairs AS (
    SELECT
        ds1.Product_SK as Product_A_SK,
        ds2.Product_SK as Product_B_SK,
        COUNT(*) as Times_Sold_Together, 
        COUNT(DISTINCT ds1.Date_SK) as Days_Sold_Together
    FROM Daily_Store_Sales ds1
    JOIN Daily_Store_Sales ds2 ON ds1.Date_SK = ds2.Date_SK
    AND ds1.Store_SK = ds2.Store_SK
    AND ds1.Product_SK < ds2.Product_SK -- Avoids duplicate pairs (A-B, B-A) and self-pairs (A-A)
    GROUP BY ds1.Product_SK, ds2.Product_SK
    HAVING COUNT(*) >= 5 -- Products sold together on at least 5 separate occasions
)
SELECT TOP 50 
    dp1.Product_ID as Product_A,
    dp1.Category as Category_A,
    dp2.Product_ID as Product_B,
    dp2.Category as Category_B,
    pp.Times_Sold_Together,
    pp.Days_Sold_Together,
    CASE
        WHEN pp.Times_Sold_Together >= 20 THEN 'STRONG AFFINITY'
        WHEN pp.Times_Sold_Together >= 10 THEN 'MODERATE AFFINITY'
        ELSE 'WEAK AFFINITY'
    END as Affinity_Strength,
    CASE
        WHEN dp1.Category != dp2.Category THEN 'Cross-Category Opportunity'
        ELSE 'Same Category Bundle'
    END as Bundle_Type
FROM Product_Pairs pp
JOIN Dim_Product dp1 ON pp.Product_A_SK = dp1.Product_SK
JOIN Dim_Product dp2 ON pp.Product_B_SK = dp2.Product_SK
ORDER BY pp.Times_Sold_Together DESC;


--***********************************************************************--

-- Query 3: Regional Inventory Efficiency Comparison 

-- Declare and set a variable for the most recent date for efficiency and clarity
DECLARE @MaxDate DATE;
SET @MaxDate = (SELECT MAX(Date) FROM Dim_Date);

WITH Regional_Metrics AS (
    SELECT
        ds.Region,
        COUNT(DISTINCT ds.Store_ID) as Number_of_Stores,
        COUNT(DISTINCT f.Product_SK) as Unique_Products,
        SUM(f.Inventory_Level) as Total_Inventory_Units,
        SUM(f.Units_Sold) as Total_Units_Sold,
        SUM(f.Units_Sold * f.Price) as Total_Revenue,
        AVG(f.Inventory_Level) as Avg_Inventory_Level,
        COUNT(CASE WHEN f.Inventory_Level = 0 THEN 1 END) as Stockout_Count,
        COUNT(*) as Total_Records
    FROM Fact_Inventory_Sales f
    JOIN Dim_Store ds ON f.Store_SK = ds.Store_SK
    JOIN Dim_Date dd ON f.Date_SK = dd.Date_SK
    WHERE dd.Date >= DATEADD(day, -30, @MaxDate)
    GROUP BY ds.Region
),
Regional_Comparison AS (
    SELECT
        *,
        ROUND(Total_Units_Sold * 1.0 / NULLIF(Total_Inventory_Units, 0), 3) as Inventory_Turnover_Rate,
        ROUND(Stockout_Count * 100.0 / Total_Records, 2) as Stockout_Rate_Percent,
        ROUND(Total_Revenue / Number_of_Stores, 2) as Revenue_Per_Store,
        ROUND(Total_Inventory_Units / Number_of_Stores, 0) as Avg_Inventory_Per_Store
    FROM Regional_Metrics
)
SELECT
    Region,
    Number_of_Stores,
    Unique_Products,
    Total_Inventory_Units,
    Total_Units_Sold,
    ROUND(Total_Revenue, 2) as Total_Revenue,
    Inventory_Turnover_Rate,
    Stockout_Rate_Percent,
    Revenue_Per_Store,
    Avg_Inventory_Per_Store,
    CASE
        WHEN Inventory_Turnover_Rate > 0.5 AND Stockout_Rate_Percent < 5 THEN 'EXCELLENT'
        WHEN Inventory_Turnover_Rate > 0.3 AND Stockout_Rate_Percent < 10 THEN 'GOOD'
        WHEN Inventory_Turnover_Rate > 0.2 OR Stockout_Rate_Percent < 15 THEN 'AVERAGE'
        ELSE 'NEEDS IMPROVEMENT'
    END as Performance_Rating,
    RANK() OVER (ORDER BY Inventory_Turnover_Rate DESC) as Turnover_Rank,
    RANK() OVER (ORDER BY Stockout_Rate_Percent ASC) as Stockout_Rank
FROM Regional_Comparison
ORDER BY Inventory_Turnover_Rate DESC;





