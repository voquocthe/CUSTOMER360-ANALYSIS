-- show data of tables 
SELECT * FROM customer_registered cr;
SELECT * FROM customer_transaction ct;
SELECT * FROM location l;
SELECT * FROM rfm_statistics rs ;
-- Choosing the report date
SET @report_date = '2022-09-01'
-- rfm calculation
CREATE TABLE rfm_project.rfm_statistics (WITH rfm_table AS (
SELECT ct.customerid
-- "recency" calculation
,DATEDIFF(@report_date, MAX(ct.purchase_date)) AS 'recency'
-- "frequency" calculation
, round(1.0 *(count(DISTINCT ct.purchase_date))/datediff(@report_date,cr.created_date),4) AS 'frequency'
-- "monetary" calculation
, round(1.0* sum(gmv)/DATEDIFF(@report_date,cr.created_date),4) AS 'monetary'
	FROM customer_transaction ct
    JOIN customer_registered cr
    ON ct.customerid = cr.id
-- Filter out customers whose stopdate is different "NULL"
    WHERE cr.stopdate = ""
    GROUP BY ct.customerid),
-- rfm_statistics
rfm_statistics AS (
SELECT rfm.customerid, rfm.recency, rfm.frequency, rfm.monetary
-- arrange the order of R
,ROW_NUMBER() OVER (ORDER BY rfm.recency DESC) AS 'rank_recency'
-- arrange the order of F
,ROW_NUMBER() OVER (ORDER BY rfm.frequency ASC) AS 'rank_frequency'
-- arrange the order of M
,ROW_NUMBER() OVER (ORDER BY rfm.monetary ASC) AS 'rank_monetary'
FROM rfm_table rfm
GROUP BY rfm.customerid)
SELECT * FROM rfm_statistics);
-- Divided by IQR(interquartile range)
WITH RFM_IQR AS (
SELECT r.CustomerID, r.recency, r.frequency, r.monetary,
-- Recency_IQR
CASE 
	WHEN r.recency <= (SELECT max(rs.recency) FROM rfm_statistics rs)  
		AND r.recency >= (SELECT rs.recency FROM rfm_statistics rs WHERE rs.rank_recency = (SELECT round(count(rs.customerid)*0.25,0) FROM rfm_statistics rs))
		THEN 1
	WHEN r.recency < (SELECT rs.recency FROM rfm_statistics rs WHERE rs.rank_recency = (SELECT round(count(rs.customerid)*0.25,0) FROM rfm_statistics rs))
		AND r.recency >= (SELECT rs.recency FROM rfm_statistics rs WHERE rs.rank_recency = (SELECT round(count(rs.customerid)*0.5,0) FROM rfm_statistics rs))
		THEN 2
	WHEN r.recency < (SELECT rs.recency FROM rfm_statistics rs WHERE rs.rank_recency = (SELECT round(count(rs.customerid)*0.5,0) FROM rfm_statistics rs))
		AND r.recency >= (SELECT rs.recency FROM rfm_statistics rs WHERE rs.rank_recency = (SELECT round(count(rs.customerid)*0.75,0) FROM rfm_statistics rs))
		THEN 3
	ELSE 4 END AS "R",
-- Frequency_IQR
CASE 
	WHEN r.frequency >= (SELECT min(rs.frequency) FROM rfm_statistics rs)  
		AND r.frequency <= (SELECT rs.frequency FROM rfm_statistics rs WHERE rs.rank_frequency = (SELECT round(count(rs.customerid)*0.25,0) FROM rfm_statistics rs))
		THEN 1
	WHEN r.frequency > (SELECT rs.frequency FROM rfm_statistics rs WHERE rs.rank_frequency = (SELECT round(count(rs.customerid)*0.25,0) FROM rfm_statistics rs))
		AND r.frequency <= (SELECT rs.frequency FROM rfm_statistics rs WHERE rs.rank_frequency = (SELECT round(count(rs.customerid)*0.5,0) FROM rfm_statistics rs))
		THEN 2
	WHEN r.frequency > (SELECT rs.frequency FROM rfm_statistics rs WHERE rs.rank_frequency = (SELECT round(count(rs.customerid)*0.5,0) FROM rfm_statistics rs))
		AND r.frequency <= (SELECT rs.frequency FROM rfm_statistics rs WHERE rs.rank_frequency = (SELECT round(count(rs.customerid)*0.75,0) FROM rfm_statistics rs))
		THEN 3
	ELSE 4 END AS "F",
-- Monetary_IQR
CASE  
	WHEN r.monetary >= (SELECT min(rs.monetary) FROM rfm_statistics rs)  
		AND r.monetary <= (SELECT rs.monetary FROM rfm_statistics rs WHERE rs.rank_monetary = (SELECT round(count(rs.customerid)*0.25,0) FROM rfm_statistics rs))
		THEN 1
	WHEN r.monetary > (SELECT rs.monetary FROM rfm_statistics rs WHERE rs.rank_monetary = (SELECT round(count(rs.customerid)*0.25,0) FROM rfm_statistics rs))
		AND r.monetary <= (SELECT rs.monetary FROM rfm_statistics rs WHERE rs.rank_monetary = (SELECT round(count(rs.customerid)*0.5,0) FROM rfm_statistics rs))
		THEN 2
	WHEN r.monetary > (SELECT rs.monetary FROM rfm_statistics rs WHERE rs.rank_monetary = (SELECT round(count(rs.customerid)*0.5,0) FROM rfm_statistics rs))
		AND r.monetary <= (SELECT rs.monetary FROM rfm_statistics rs WHERE rs.rank_monetary = (SELECT round(count(rs.customerid)*0.75,0) FROM rfm_statistics rs))
		THEN 3
		ELSE 4 END AS "M"
	FROM rfm_statistics r),
-- CONCAT RFM IQR
CONCAT_RFM_IQR AS (SELECT concat(r.R,r.F,r.M) AS 'concat_IQR', count(r.CustomerID) AS 'count'
		FROM RFM_IQR r
		GROUP BY r.R,r.F,r.M)
-- Group customers
SELECT CASE
	WHEN c.concat_IQR IN ('444', '443', '434', '344', '334')
		THEN 'VIP customers'
	WHEN c.concat_IQR IN ('433', '424', '423', '414', '413', '343', '333', '324', '323','314', '313')
		THEN 'Loyal customers'
	WHEN c.concat_IQR IN ('442', '432', '422', '412', '342', '332', '322', '312', '242', '233', '244', '243', '234', '224', '223', '214', '213')
		THEN 'Potential customers'
	ELSE 'Visiting customers'
	END AS 'Group_customers', sum(c.count) AS 'count'
	FROM CONCAT_RFM_IQR c
	GROUP BY Group_customers;
	