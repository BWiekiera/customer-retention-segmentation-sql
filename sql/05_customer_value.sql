-- Customer Retention & Segmentation Analysis
-- 05. Customer value and concentration

create or replace view analytics.customer_value as
select
    customer_id
    ,count(*) as order_count
    ,sum(order_value) as total_customer_value
    ,round(avg(order_value), 2) as avg_order_value
from analytics.customer_orders
group by customer_id;

-- Customer value ranking and cumulative share
select
    customer_id
    ,order_count
    ,total_customer_value
    ,avg_order_value
    ,dense_rank() over (
        order by total_customer_value desc
    ) as customer_value_rank
    ,round(
        total_customer_value * 100.0
        / sum(total_customer_value) over ()
        ,4
    ) as customer_value_share_pct
    ,sum(total_customer_value) over (
        order by total_customer_value desc
        rows between unbounded preceding and current row
    ) as cumulative_customer_value
    ,round(
        sum(total_customer_value) over (
            order by total_customer_value desc
            rows between unbounded preceding and current row
        ) * 100.0
        / sum(total_customer_value) over ()
        ,4
    ) as cumulative_value_share_pct
from analytics.customer_value
order by total_customer_value desc
limit 20;

-- Concentration: number of customers needed to reach 80% of gross purchase value
with customer_concentration_CTE as (
    select
        customer_id
        ,total_customer_value
        ,row_number() over (
            order by total_customer_value desc, customer_id
        ) as customer_nr
        ,count(*) over () as total_customer_count
        ,round(
            sum(total_customer_value) over (
                order by total_customer_value desc, customer_id
                rows between unbounded preceding and current row
            ) * 100.0
            / sum(total_customer_value) over ()
            ,4
        ) as cumulative_value_share_pct
    from analytics.customer_value
)
select
    customer_nr as customers_needed_for_80_pct
    ,total_customer_count
    ,round(
        customer_nr * 100.0 / total_customer_count
        ,2
    ) as customer_share_pct
    ,cumulative_value_share_pct
from customer_concentration_CTE
where cumulative_value_share_pct >= 80
order by customer_nr
limit 1;

-- Change in customer gross purchase value between source periods
with customer_period_value_CTE as (
    select
        customer_id
        ,sum(order_value) filter (
            where source_period = '2009-2010'
        ) as customer_value_2009_2010
        ,sum(order_value) filter (
            where source_period = '2010-2011'
        ) as customer_value_2010_2011
    from analytics.customer_orders
    group by customer_id
),
customer_value_change_CTE as (
    select
        customer_id
        ,coalesce(customer_value_2009_2010, 0) as customer_value_2009_2010
        ,coalesce(customer_value_2010_2011, 0) as customer_value_2010_2011
        ,coalesce(customer_value_2010_2011, 0)
         - coalesce(customer_value_2009_2010, 0) as customer_value_change
        ,case
            when customer_value_2009_2010 is null
                then 'new_in_2010_2011'
            when customer_value_2010_2011 is null
                then 'not_retained_in_2010_2011'
            when customer_value_2009_2010 < customer_value_2010_2011
                then 'value_increased'
            when customer_value_2009_2010 > customer_value_2010_2011
                then 'value_decreased'
            else 'value_unchanged'
        end as customer_value_status
        ,round(
            (
                coalesce(customer_value_2010_2011, 0)
                - coalesce(customer_value_2009_2010, 0)
            ) * 100.0
            / nullif(customer_value_2009_2010, 0)
            ,2
        ) as customer_value_change_pct
    from customer_period_value_CTE
)
select
    customer_value_status
    ,count(*) as customer_count
    ,round(
        count(*) * 100.0 / sum(count(*)) over ()
        ,2
    ) as customer_share_pct
    ,sum(customer_value_2009_2010) as total_value_2009_2010
    ,sum(customer_value_2010_2011) as total_value_2010_2011
    ,sum(customer_value_change) as total_value_change
from customer_value_change_CTE
group by customer_value_status
order by customer_count desc;

-- Overall change between source periods
with customer_period_value_CTE as (
    select
        customer_id
        ,sum(order_value) filter (
            where source_period = '2009-2010'
        ) as customer_value_2009_2010
        ,sum(order_value) filter (
            where source_period = '2010-2011'
        ) as customer_value_2010_2011
    from analytics.customer_orders
    group by customer_id
),
customer_value_change_CTE as (
    select
        customer_id
        ,coalesce(customer_value_2009_2010, 0) as customer_value_2009_2010
        ,coalesce(customer_value_2010_2011, 0) as customer_value_2010_2011
        ,coalesce(customer_value_2010_2011, 0)
         - coalesce(customer_value_2009_2010, 0) as customer_value_change
    from customer_period_value_CTE
)
select
    sum(customer_value_2009_2010) as overall_value_2009_2010
    ,sum(customer_value_2010_2011) as overall_value_2010_2011
    ,sum(customer_value_change) as overall_value_change
    ,round(
        sum(customer_value_change) * 100.0
        / nullif(sum(customer_value_2009_2010), 0)
        ,2
    ) as overall_value_change_pct
from customer_value_change_CTE;
