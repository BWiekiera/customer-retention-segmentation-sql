-- Customer Retention & Segmentation Analysis
-- 07. Cohort retention and customer lifecycle

-- Cohorts are based on the first purchase observed in the available dataset.
create or replace view analytics.customer_cohorts as
select
    customer_id
    ,min(order_date)::date as first_purchase_date
    ,date_trunc('month', min(order_date))::date as cohort_month
from analytics.customer_order_sequence
group by customer_id;

create or replace view analytics.customer_cohort_orders as
with cohort_orders_CTE as (
    select
        os.invoice
        ,os.customer_id
        ,os.order_date
        ,cc.cohort_month
        ,date_trunc('month', os.order_date)::date as order_month
    from analytics.customer_order_sequence os
    join analytics.customer_cohorts cc
        on os.customer_id = cc.customer_id
)
select
    invoice
    ,customer_id
    ,order_date
    ,cohort_month
    ,order_month
    ,(
        (extract(year from order_month) - extract(year from cohort_month)) * 12
        + (extract(month from order_month) - extract(month from cohort_month))
    )::int as cohort_index
from cohort_orders_CTE;

-- Monthly active customers and retention rate by cohort
create or replace view analytics.customer_cohort_retention as
with cohort_activity_CTE as (
    select
        cohort_month
        ,cohort_index
        ,count(distinct customer_id) as active_customers
    from analytics.customer_cohort_orders
    group by
        cohort_month
        ,cohort_index
),
cohort_size_CTE as (
    select
        cohort_month
        ,cohort_index
        ,active_customers
        ,first_value(active_customers) over (
            partition by cohort_month
            order by cohort_index
        ) as cohort_size
    from cohort_activity_CTE
)
select
    cohort_month
    ,cohort_index
    ,active_customers
    ,cohort_size
    ,round(
        active_customers * 100.0 / cohort_size
        ,2
    ) as retention_rate
from cohort_size_CTE;

-- Retention validation
select
    min(cohort_index) as min_cohort_index
    ,max(cohort_index) as max_cohort_index
    ,min(retention_rate) as min_retention_rate
    ,max(retention_rate) as max_retention_rate
from analytics.customer_cohort_retention;

-- Unweighted average retention and number of observable cohorts
select
    cohort_index
    ,count(*) as cohort_count
    ,round(avg(retention_rate), 2) as avg_retention_rate
from analytics.customer_cohort_retention
group by cohort_index
order by cohort_index;

-- Weighted retention
select
    cohort_index
    ,round(
        sum(active_customers) * 100.0 / sum(cohort_size)
        ,2
    ) as weighted_retention_rate
from analytics.customer_cohort_retention
group by cohort_index
order by cohort_index;

-- Business-friendly cohort summary
create or replace view analytics.customer_cohort_summary as
select
    cohort_month
    ,max(cohort_size) as cohort_size
    ,max(retention_rate) filter (where cohort_index = 1) as month_1
    ,max(retention_rate) filter (where cohort_index = 3) as month_3
    ,max(retention_rate) filter (where cohort_index = 6) as month_6
    ,max(retention_rate) filter (where cohort_index = 12) as month_12
from analytics.customer_cohort_retention
group by cohort_month
order by cohort_month;

-- Purchase-gap percentiles used to define lifecycle thresholds
select
    percentile_cont(0.25) within group (
        order by days_since_previous_order
    ) as p25
    ,percentile_cont(0.50) within group (
        order by days_since_previous_order
    ) as median
    ,percentile_cont(0.75) within group (
        order by days_since_previous_order
    ) as p75
    ,percentile_cont(0.90) within group (
        order by days_since_previous_order
    ) as p90
from analytics.customer_order_sequence
where days_since_previous_order is not null
  and days_since_previous_order > 0;

-- Customer lifecycle and reactivation history
create or replace view analytics.customer_lifecycle as
with lifecycle_status_CTE as (
    select
        customer_id
        ,recency_days
        ,case
            when recency_days <= 70 then 'active'
            when recency_days <= 147 then 'at_risk'
            else 'inactive'
        end as lifecycle_status
    from analytics.customer_rfm
),
reactivation_count_CTE as (
    select
        customer_id
        ,count(*) filter (
            where days_since_previous_order > 147
        ) as reactivation_count
        ,max(order_date) filter (
            where days_since_previous_order > 147
        )::date as last_reactivation_date
    from analytics.customer_order_sequence
    group by customer_id
    having count(*) filter (
        where days_since_previous_order > 147
    ) > 0
)
select
    ls.customer_id
    ,ls.recency_days
    ,ls.lifecycle_status
    ,coalesce(rc.reactivation_count, 0) as reactivation_count
    ,rc.last_reactivation_date
    ,case
        when rc.reactivation_count is null then 'not_reactivated'
        else 'reactivated'
    end as reactivation_flag
from lifecycle_status_CTE ls
left join reactivation_count_CTE rc
    on ls.customer_id = rc.customer_id;

-- Lifecycle distribution
select
    lifecycle_status
    ,count(*) as customer_count
    ,round(
        count(*) * 100.0 / sum(count(*)) over ()
        ,2
    ) as customer_share_pct
from analytics.customer_lifecycle
group by lifecycle_status
order by customer_count desc;

-- Reactivation by current lifecycle status
select
    lifecycle_status
    ,reactivation_flag
    ,count(*) as customer_count
    ,round(
        count(*) * 100.0
        / sum(count(*)) over (partition by lifecycle_status)
        ,2
    ) as status_share_pct
from analytics.customer_lifecycle
group by
    lifecycle_status
    ,reactivation_flag
order by
    lifecycle_status
    ,reactivation_flag;

-- Validation
select
    count(*) as customer_count
    ,count(distinct customer_id) as unique_customer_count
    ,count(*) filter (where lifecycle_status is null) as missing_lifecycle_status
    ,count(*) filter (where reactivation_flag is null) as missing_reactivation_flag
    ,count(*) filter (
        where reactivation_count = 0
          and last_reactivation_date is not null
    ) as invalid_zero_reactivation_date
    ,count(*) filter (
        where reactivation_count > 0
          and last_reactivation_date is null
    ) as missing_reactivation_date
from analytics.customer_lifecycle;
