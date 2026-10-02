-- Customer Retention & Segmentation Analysis
-- 06. RFM segmentation

-- RFM metrics use positive customer purchases observed in the available period.
create or replace view analytics.customer_rfm as
with analysis_date_CTE as (
    select
        max(order_date)::date + 1 as analysis_date
    from analytics.customer_orders
)
select
    customer_id
    ,max(order_date)::date as last_order_date
    ,analysis_date - max(order_date)::date as recency_days
    ,count(*) as frequency
    ,sum(order_value) as monetary
from analytics.customer_orders
cross join analysis_date_CTE
group by
    customer_id
    ,analysis_date;

-- Percentile-based RFM segmentation
create or replace view analytics.customer_rfm_segments as
with rfm_percentiles_CTE as (
    select
        *
        ,percent_rank() over (
            order by recency_days desc
        ) as r_percentile
        ,percent_rank() over (
            order by frequency
        ) as f_percentile
        ,percent_rank() over (
            order by monetary
        ) as m_percentile
    from analytics.customer_rfm
)
select
    *
    ,case
        when frequency = 1
         and r_percentile >= 0.75
            then 'new_customer'
        when r_percentile >= 0.75
         and f_percentile >= 0.75
         and m_percentile >= 0.75
            then 'champion'
        when r_percentile >= 0.50
         and f_percentile >= 0.50
            then 'loyal_customer'
        when r_percentile >= 0.50
         and f_percentile < 0.50
            then 'potential_loyalist'
        when r_percentile < 0.50
         and (f_percentile >= 0.50 or m_percentile >= 0.75)
            then 'at_risk'
        else 'hibernating'
    end as rfm_segment
    ,case
        when m_percentile >= 0.99 then 'exceptional_value'
        when m_percentile >= 0.90 then 'very_high_value'
        when m_percentile >= 0.75 then 'high_value'
        else 'standard_value'
    end as value_tier
from rfm_percentiles_CTE;

-- Segment summary
select
    rfm_segment
    ,count(*) as customer_count
    ,round(
        count(*) * 100.0 / sum(count(*)) over ()
        ,2
    ) as customer_share_pct
    ,round(avg(recency_days), 2) as avg_recency_days
    ,round(avg(frequency), 2) as avg_frequency
    ,round(avg(monetary), 2) as avg_monetary
    ,round(sum(monetary), 2) as gross_purchase_value
    ,round(
        sum(monetary) * 100.0 / sum(sum(monetary)) over ()
        ,2
    ) as gross_purchase_value_share_pct
from analytics.customer_rfm_segments
group by rfm_segment
order by gross_purchase_value desc;

-- Validation
select
    count(*) as customer_count
    ,count(distinct customer_id) as unique_customer_count
    ,count(*) filter (where rfm_segment is null) as missing_rfm_segment_count
    ,count(*) filter (where value_tier is null) as missing_value_tier_count
    ,round(sum(monetary), 2) as total_monetary
from analytics.customer_rfm_segments;
