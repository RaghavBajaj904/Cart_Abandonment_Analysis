USE cart_abandonment;

CREATE INDEX idx_session_event
ON ecommerce_events (user_session, event_type);



-- AGG FUNNEL SUMMARY
DROP TABLE IF EXISTS agg_funnel_summary;
CREATE TABLE agg_funnel_summary AS
WITH session_events AS (
	SELECT user_session,
    MAX(CASE WHEN event_type = 'view' THEN 1 ELSE 0 END) AS has_view,
    MAX(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS has_cart,
    MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS has_purchase
    FROM ecommerce_events
    GROUP BY user_session
)
SELECT COUNT(*) AS total_sessions,
SUM(has_view) AS view_sessions,
SUM(has_cart) AS cart_sessions,
SUM(CASE WHEN has_cart = 1 AND has_purchase = 1 THEN 1 ELSE 0 END) AS purchase_sessions,
(SUM(has_view) - SUM(has_cart)) AS view_to_cart_dropoff_volume,
(SUM(has_cart) - SUM(CASE WHEN has_cart = 1  AND has_purchase = 1 THEN 1 ELSE 0 END)) AS cart_to_purchase_dropoff_volume,
ROUND((SUM(has_view) - SUM(has_cart)) * 100 / NULLIF(SUM(has_view), 0), 2) AS view_to_cart_dropoff_pct,
ROUND((SUM(has_cart) - SUM(CASE WHEN has_cart = 1  AND has_purchase = 1 THEN 1 ELSE 0 END)) *100 / NULLIF(SUM(has_cart),0), 2) AS cart_to_purchase_dropoff_pct
FROM session_events;


DROP TABLE IF EXISTS agg_platform_lost_gmv_summary;
-- AGG PLATFORM LOST GMV SUMMARY
CREATE TABLE agg_platform_lost_gmv_summary AS 
WITH item_sessions_flags AS (
SELECT user_session, product_id,
AVG(price) AS price,
MAX(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) as was_carted,
MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) as was_purchased
FROM ecommerce_events
WHERE event_type IN ('cart', 'purchase')
GROUP BY user_session, product_id
)
SELECT 
ROUND(SUM(CASE WHEN was_carted = 1 AND was_purchased = 0 THEN price ELSE 0 END ), 2) AS total_lost_gmv_usd,
SUM(was_carted) AS total_item_cart_sessions,
SUM(was_purchased) AS total_item_purchase_sessions,
(SUM(was_carted) - SUM(was_purchased)) AS total_cart_to_purchase_dropff_item_sessions,
ROUND((SUM(was_carted) - SUM(was_purchased)) * 100 / NULLIF(SUM(was_carted), 0), 2) AS item_cart_to_purchase_dropff_pct
FROM item_sessions_flags;




CREATE INDEX idx_main_cat_sub_cat_product_type_price
ON ecommerce_events (main_category, sub_category, product_type, price);
CREATE INDEX idx_brand
ON ecommerce_events (brand);
CREATE INDEX idx_product_id ON ecommerce_events (product_id);





-- AGG CATEGORY BRAND FUNNEL
CREATE TABLE agg_category_brand_funnel AS
WITH item_sessions_flags AS(
SELECT
	user_session,
    product_id,
    ANY_VALUE(main_category) AS main_category,
    ANY_VALUE(sub_category) AS sub_category,
    ANY_VALUE(product_type) AS product_type,
    ANY_VALUE(brand) AS brand,
    AVG(price) AS price,
    MAX(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS was_carted,
    MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS was_purchased
FROM ecommerce_events
WHERE event_type IN ('cart', 'purchase') AND brand != 'Unknown' AND main_category != 'Unknown'
GROUP BY user_session, product_id
)
SELECT 
    main_category,
    sub_category,
    product_type,
    brand,
    SUM(was_carted) AS cart_count,
    SUM(was_purchased) AS purchase_count,
	(SUM(was_carted) - SUM(was_purchased)) AS abandoned_cart_count,
    ROUND(SUM(CASE WHEN was_carted = 1 AND was_purchased = 0 THEN price ELSE 0 END), 2) AS total_lost_gmv_usd,
    ROUND(((SUM(was_carted) - SUM(was_purchased)) * 100.0) / NULLIF(SUM(was_carted), 0), 2) AS abandonment_rate_pct
FROM item_sessions_flags
GROUP BY main_category, sub_category, product_type, brand
HAVING cart_count >=100
ORDER BY total_lost_gmv_usd DESC;





-- AGG TOP ABANDONED PRODUCTS
CREATE TABLE agg_nov_top_abandoned_products AS
WITH item_sessions_flags AS (
    SELECT 
        user_session,
        product_id,
        ANY_VALUE(main_category) AS main_category,
        ANY_VALUE(sub_category) AS sub_category,
        ANY_VALUE(product_type) AS product_type,
        ANY_VALUE(brand) AS brand,
        AVG(price) AS price,
        MAX(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS was_carted,
        MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS was_purchased
    FROM ecommerce_events
    WHERE event_type IN ('cart', 'purchase') 
      AND brand != 'Unknown' 
      AND main_category != 'Unknown'
    GROUP BY user_session, product_id
)
SELECT 
    product_id,
    ANY_VALUE(main_category) AS main_category,
    ANY_VALUE(sub_category) AS sub_category,
    ANY_VALUE(product_type) AS product_type,
    ANY_VALUE(brand) AS brand,
    ROUND(AVG(price), 2) AS avg_price_usd,
    SUM(was_carted) AS cart_count,
    SUM(was_purchased) AS purchase_count,
    (SUM(was_carted) - SUM(was_purchased)) AS abandoned_cart_count,
    ROUND(SUM(CASE WHEN was_carted = 1 AND was_purchased = 0 THEN price ELSE 0 END), 2) AS total_lost_gmv_usd,
    ROUND(((SUM(was_carted) - SUM(was_purchased)) * 100.0) / NULLIF(SUM(was_carted), 0), 2) AS abandonment_rate_pct
FROM item_sessions_flags
GROUP BY product_id
HAVING cart_count >= 100
ORDER BY total_lost_gmv_usd DESC
LIMIT 100;





-- AGG PRICE TIER FUNNEL
DROP TABLE IF EXISTS agg_price_tier_funnel;
CREATE TABLE agg_price_tier_funnel AS
WITH item_sessions_flags AS (
SELECT user_session, product_id, AVG(price) AS price,
	CASE WHEN AVG(price) < 50 THEN '1. Under $50 (Budget)'
	WHEN AVG(price) BETWEEN 50 AND 149.99 THEN '2. $50 - $150 (Mid-range)'
	WHEN AVG(price) BETWEEN 150 AND 499.99 THEN '3. $150 - $500 (Core)'
	WHEN AVG(price) BETWEEN 500 AND 999.99 THEN '4. $500 - $1000 (Premium)'
	ELSE '5. Above $1000 (Ultra-Premium)'
	END AS price_tier,
	MAX(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS was_carted,
	MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS was_purchased
FROM ecommerce_events
WHERE event_type IN ('cart', 'purchase')
GROUP BY user_session, product_id
)
SELECT price_tier,
	SUM(was_carted)  AS item_cart_sessions,
	SUM(was_purchased) AS item_purchase_sessions,
	SUM(was_carted) - SUM(was_purchased) AS cart_to_purchase_dropff_item_sessions,
	ROUND(SUM(CASE WHEN was_carted = 1 AND was_purchased = 0 THEN price ELSE 0 END), 2) AS total_lost_gmv_usd,
	ROUND(((SUM(was_carted) - SUM(was_purchased)) * 100.0) / NULLIF(SUM(was_carted), 0), 2) AS cart_to_purchase_dropoff_rate_pct
FROM item_sessions_flags
GROUP BY price_tier
ORDER BY price_tier ASC;






CREATE INDEX idx_event_session_prod_time 
ON ecommerce_events(event_type, user_session, product_id, event_time);




DROP TABLE IF EXISTS agg_temporal_abandonment_patterns;
CREATE TABLE agg_temporal_abandonment_patterns AS
WITH item_cart_summary AS (
SELECT user_session, product_id, AVG(price) AS price,
MIN(event_time) AS cart_time,
MAX(CASE WHEN event_type = 'cart' THEN 1 ELSE 0 END) AS was_carted,
MAX(CASE WHEN event_type = 'purchase' THEN 1 ELSE 0 END) AS was_purchased
FROM ecommerce_events
WHERE event_type IN ('cart', 'purchase')
GROUP BY user_session, product_id
HAVING was_carted = 1
)
SELECT
	DAYOFWEEK(cart_time) AS day_of_week_num,
    DAYNAME(cart_time) AS day_of_week,
    HOUR(cart_time) AS hour_of_day,
    SUM(was_carted)  AS total_cart_sessions,
	SUM(was_purchased) AS total_purchase_sessions,
	SUM(was_carted) - SUM(was_purchased) AS abandoned_sessions,
	ROUND(SUM(CASE WHEN was_carted = 1 AND was_purchased = 0 THEN price ELSE 0 END), 2) AS total_lost_gmv_usd,
	ROUND(((SUM(was_carted) - SUM(was_purchased)) * 100.0) / NULLIF(SUM(was_carted), 0), 2) AS abandonment_rate_pct
    FROM item_cart_summary
GROUP BY DAYOFWEEK(cart_time), DAYNAME(cart_time), HOUR(cart_time)
ORDER BY day_of_week_num, hour_of_day;