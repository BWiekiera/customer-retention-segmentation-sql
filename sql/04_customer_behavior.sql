-- Customer Retention & Segmentation Analysis
-- 04. Customer behavior

-- One-time vs returning customers
create or replace view analytics.customer_behavior as
with order_count_CTE as (
    select
        customer_id
        ,min(order_date) as first_order_date
        ,max(order_date) as last_order_date
        ,count(*) as order_count
        ,max(order_date)::date - min(order_date)::date as customer_lifetime_days
    from analytics.customer_orders
    group by customer_id
)
select
    customer_id
    ,first_order_date
    ,last_order_date
    ,order_count
    ,customer_lifetime_days
    ,case
        when order_count = 1 then 'one_time'
        else 'returning'
    end as customer_type
from order_count_CTE;

select
    customer_type
    ,count(*) as customer_count
    ,round(
        count(*) * 100.0 / sum(count(*)) over ()
        ,2
    ) as customer_share_pct
    ,sum(order_count) as total_orders
    ,round(
        sum(order_count) * 100.0 / sum(sum(order_count)) over ()
        ,2
    ) as order_share_pct
from analytics.customer_behavior
group by customer_type
order by customer_count desc;

-- Order sequence and gaps between customer purchases
create or replace view analytics.customer_order_sequence as
with order_sequence_CTE as (
    select
        customer_id
        ,invoice
        ,order_date
        ,order_value
        ,row_number() over (
            partition by customer_id
            order by order_date, invoice
        ) as order_number
        ,lag(order_date) over (
            partition by customer_id
            order by order_date, invoice
        ) as previous_order_date
    from analytics.customer_orders
)
select
    customer_id
    ,invoice
    ,order_date
    ,order_value
    ,order_number
    ,previous_order_date
    ,order_date::date - previous_order_date::date as days_since_previous_order
from order_sequence_CTE;

-- Return-time metrics
select
    count(*) filter (
        where order_number = 2
    ) as returning_customer_count
    ,round(
        avg(days_since_previous_order) filter (
            where order_number = 2
        )
        ,2
    ) as avg_days_to_second_order
    ,min(days_since_previous_order) filter (
        where order_number = 2
    ) as min_days_to_second_order
    ,max(days_since_previous_order) filter (
        where order_number = 2
    ) as max_days_to_second_order
    ,round(
        avg(days_since_previous_order) filter (
            where previous_order_date is not null
        )
        ,2
    ) as avg_days_between_orders
from analytics.customer_order_sequence;
