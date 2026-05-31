
/*  Queries for Sales Performance and Demand Analysis    */

--- QUery 1: Product Sales VElocity
-- This query calculates sales velocity for each product.
SELECT 
	p.Product_ID, 
	p.Category, 
	AVG(CAST(f.Units_Sold AS DECIMAL(10, 2))) AS Avg_Daily_Sales, 
	AVG(CAST(f.Units_Sold AS DECIMAL(10, 2))) * 7 AS Estimated_Weekly_Sales, 
	AVG(CAST(f.Units_Sold AS DECIMAL(10, 2))) * 30 AS Estimated_Monthly_Sales
FROM Fact_Inventory_Sales f
JOIN Dim_Product p ON f.Product_SK = p.Product_SK
GROUP BY p.Product_ID, p.Category
ORDER BY p.Category, Avg_Daily_Sales DESC;


--*************************************************************************--

-- Query 2: Revenue Analysis by Region and Category
--This query compares total sales revenue across all regions and product categories.
SELECT 
	ds.Region, 
	dp.Category, 
	SUM(fis.Units_Sold) AS Total_Units_Sold, 
	SUM(fis.Units_Sold * fis.Price) AS Total_Revenue
FROM Fact_Inventory_Sales fis
JOIN Dim_Store ds 
ON fis.Store_SK = ds.Store_SK
JOIN Dim_Product dp 
ON fis.Product_SK = dp.Product_SK
GROUP BY ds.Region, dp.Category
ORDER BY ds.Region, Total_Revenue DESC;