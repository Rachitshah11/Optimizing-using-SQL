
/* Queries for Forecasting and External Factor Analysis */


-- Query 1: Demand Forecasting Based on Historical Trends 

-- Declare and set a variable for the most recent date
DECLARE @MaxDate DATE;
SET @MaxDate = (SELECT MAX(Date) FROM Dim_Date);

WITH Monthly_Sales AS (
    SELECT
        f.Product_SK,
        f.Store_SK,
        dd.Year,
        dd.Month,
        -- Recreate the first day of the month to use for accurate date comparisons later
        DATEFROMPARTS(dd.Year, dd.Month, 1) AS Month_Start_Date,
        SUM(f.Units_Sold) AS Monthly_Units_Sold
    FROM Fact_Inventory_Sales f
    JOIN Dim_Date dd ON f.Date_SK = dd.Date_SK
    WHERE dd.Date >= DATEADD(month, -12, @MaxDate)
    GROUP BY f.Product_SK, f.Store_SK, dd.Year, dd.Month
),
Trend_Analysis AS (
    SELECT
        ms.Product_SK,
        ms.Store_SK,
        AVG(CAST(ms.Monthly_Units_Sold AS FLOAT)) AS Avg_Monthly_Sales,
        STDEV(ms.Monthly_Units_Sold) AS Sales_Volatility,
        AVG(CASE
                WHEN ms.Month_Start_Date >= DATEADD(month, -3, @MaxDate)
                THEN ms.Monthly_Units_Sold
            END) AS Recent_3_Month_Avg,
        AVG(CASE
                WHEN ms.Month_Start_Date BETWEEN DATEADD(month, -6, @MaxDate) AND DATEADD(month, -4, @MaxDate)
                THEN ms.Monthly_Units_Sold
            END) AS Previous_3_Month_Avg
    FROM Monthly_Sales ms
    GROUP BY ms.Product_SK, ms.Store_SK
)
SELECT
    dp.Product_ID,
    dp.Category,
    ds.Store_ID,
    ds.Region,
    ROUND(ta.Avg_Monthly_Sales, 0) AS Avg_Monthly_Sales,
    -- Use COALESCE to handle cases where volatility might be NULL 
    ROUND(COALESCE(ta.Sales_Volatility, 0), 0) AS Sales_Volatility,
    ROUND(COALESCE(ta.Recent_3_Month_Avg, 0), 0) AS Recent_3_Month_Avg,
    ROUND(COALESCE(ta.Previous_3_Month_Avg, 0), 0) AS Previous_3_Month_Avg,
    CASE
        -- Added COALESCE to handle NULL averages 
        WHEN COALESCE(ta.Recent_3_Month_Avg, 0) > COALESCE(ta.Previous_3_Month_Avg, 0) * 1.1 THEN 'GROWING'
        WHEN COALESCE(ta.Recent_3_Month_Avg, 0) < COALESCE(ta.Previous_3_Month_Avg, 0) * 0.9 THEN 'DECLINING'
        ELSE 'STABLE'
    END AS Trend_Direction,
    -- Suggest next month's stock based on the recent average, with a buffer
    ROUND(COALESCE(ta.Recent_3_Month_Avg, ta.Avg_Monthly_Sales, 0) * 1.2, 0) AS Forecast_Next_Month
FROM Trend_Analysis ta
JOIN Dim_Product dp ON ta.Product_SK = dp.Product_SK
JOIN Dim_Store ds ON ta.Store_SK = ds.Store_SK
WHERE ta.Avg_Monthly_Sales > 0
ORDER BY ta.Avg_Monthly_Sales DESC;



--*******************************************************************************--

-- Query 2: Holiday and Promotion Impact Analysis
SELECT
CASE
WHEN f.Holiday_Promotion = 1 THEN 'HOLIDAY/PROMOTION'
ELSE 'REGULAR'
END AS Day_Type,
dp.Category,
COUNT(*) AS Number_of_Days,
SUM(f.Units_Sold) AS Total_Units_Sold,
AVG(f.Units_Sold) AS Avg_Daily_Sales,
SUM(f.Units_Sold * f.Price) AS Total_Revenue,
AVG(f.Price) AS Avg_Price
FROM Fact_Inventory_Sales f
JOIN Dim_Product dp ON f.Product_SK = dp.Product_SK
WHERE f.Units_Sold > 0
GROUP BY f.Holiday_Promotion, dp.Category
ORDER BY Day_Type, Total_Revenue DESC;


--******************************************************************************--

-- Query 3 : Demannd Forecast accuracy (MAPE)
-- This query evaluates the accuracy of demand forecasts using MAPE.
-- A lower MAPE value signifies a more accurate forecast.
SELECT 
	p.Product_ID, 
	p.Category, 
    -- MAPE = Average of (|Actual - Forecast| / Actual) * 100 
	AVG(ABS(f.Units_Sold - f.Demand_Forecast) / NULLIF(f.Units_Sold, 0)) * 100 AS MAPE
FROM Fact_Inventory_Sales f
JOIN Dim_Product p ON f.Product_SK = p.Product_SK
WHERE f.Units_Sold > 0 
-- Avoid division by zero and only include days with sales
GROUP BY p.Product_ID, p.Category
HAVING AVG(ABS(f.Units_Sold - f.Demand_Forecast) / NULLIF(f.Units_Sold, 0)) IS NOT NULL
ORDER BY MAPE DESC;


--**********************************************************************--

--Query 4: Forecast Unit Variance Analysis
-- This query calculates the total raw variance between forecasted units and sold units.
-- A positive variance means  over-forecasted (bought too much).
-- A negative variance means  under-forecasted (potentially missed sales).
SELECT 
	dp.Category, 
	ds.Region, 
	SUM(fis.Demand_Forecast) AS Total_Forecasted_Units, 
	SUM(fis.Units_Sold) AS Total_Sold_Units, 
	SUM(fis.Demand_Forecast) - SUM(fis.Units_Sold) AS Unit_Variance
FROM Fact_Inventory_Sales fis
JOIN Dim_Product dp 
ON fis.Product_SK = dp.Product_SK
JOIN Dim_Store ds 
ON fis.Store_SK = ds.Store_SK
GROUP BY dp.Category, ds.Region
ORDER BY ABS(SUM(fis.Demand_Forecast) - SUM(fis.Units_Sold)) DESC;



--***************************************************************************--

-- Query 5: Discount Impact Analysis
-- This query compares the average sales volume and average discount percentage
-- for products when they are discounted versus when they are not.
SELECT 
	dp.Category, 
	AVG(CASE WHEN fis.Discount > 0 
			THEN fis.Units_Sold 
			ELSE NULL END) AS Avg_Sales_With_Discount, 
	AVG(CASE WHEN fis.Discount = 0 
			THEN fis.Units_Sold ELSE NULL END) AS Avg_Sales_Without_Discount, 
	AVG(CASE WHEN fis.Discount > 0 
			THEN fis.Discount ELSE NULL END) AS Avg_Discount_Percent
FROM Fact_Inventory_Sales fis
JOIN Dim_Product dp ON fis.Product_SK = dp.Product_SK
GROUP BY dp.Category
ORDER BY dp.Category;