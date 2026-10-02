-- Customer Retention & Segmentation Analysis
-- 08. Cancellations and seasonality

-- Cancellation scale and value
select
    count(distinct invoice) as cancelled_invoices
    ,count(distinct customer_id) as customers_with_cancellations
    ,count(*) filter (
        where customer_id is null
    ) as cancellation_rows_without_customer
    ,sum(abs(line_value)) as cancellation_value
from staging.online_retail_prepared
where operation_type = 'cancellation';

-- Cancellation value compared with standard sale value
select
    sum(line_value) filter (
        where operation_type = 'sale'
    ) as sales_value
    ,sum(abs(line_value)) filter (
        where operation_type = 'cancellation'
    ) as cancellation_value
    ,round(
        sum(abs(line_value)) filter (
            where operation_type = 'cancellation'
        ) * 100.0
        / sum(line_value) filter (
            where operation_type = 'sale'
        )
        ,2
    ) as cancellation_value_rate
    ,sum(abs(line_value)) filter (
        where operation_type = 'cancellation'
          and customer_id is not null
    ) as cancellation_value_with_customer
    ,sum(abs(line_value)) filter (
        where operation_type = 'cancellation'
          and customer_id is null
    ) as cancellation_value_without_customer
    ,round(
        sum(abs(line_value)) filter (
            where operation_type = 'cancellation'
              and customer_id is not null
        ) * 100.0
        / sum(abs(line_value)) filter (
            where operation_type = 'cancellation'
        )
        ,2
    ) as cancellation_value_with_customer_rate
from staging.online_retail_prepared;

-- Customers with the highest cancellation value
select
    customer_id
    ,count(distinct invoice) as cancelled_invoices
    ,count(*) as cancellation_lines
    ,sum(abs(line_value)) as cancellation_value
from staging.online_retail_prepared
where operation_type = 'cancellation'
  and customer_id is not null
group by customer_id
order by cancellation_value desc
limit 10;

-- Cancellation value compared with observed gross purchase value
with purchase_value_CTE as (
    select
        customer_id
        ,sum(order_value) as purchase_value
    from analytics.customer_orders
    group by customer_id
),
cancellation_value_CTE as (
    select
        customer_id
        ,sum(abs(line_value)) as cancellation_value
    from staging.online_retail_prepared
    where operation_type = 'cancellation'
      and customer_id is not null
    group by customer_id
)
select
    c.customer_id
    ,p.purchase_value
    ,c.cancellation_value
    ,round(
        c.cancellation_value * 100.0 / p.purchase_value
        ,2
    ) as cancellation_to_purchase_rate
from cancellation_value_CTE c
left join purchase_value_CTE p
    on c.customer_id = p.customer_id
order by cancellation_value desc
limit 20;

-- Customers with cancellations >= observed gross purchases,
-- and customers with cancellations but no observed positive purchase
with purchase_value_CTE as (
    select
        customer_id
        ,sum(order_value) as purchase_value
    from analytics.customer_orders
    group by customer_id
),
cancellation_value_CTE as (
    select
        customer_id
        ,sum(abs(line_value)) as cancellation_value
    from staging.online_retail_prepared
    where operation_type = 'cancellation'
      and customer_id is not null
    group by customer_id
),
customer_cancellation_CTE as (
    select
        c.customer_id
        ,p.purchase_value
        ,c.cancellation_value
        ,c.cancellation_value * 100.0 / p.purchase_value as cancellation_to_purchase_rate
    from cancellation_value_CTE c
    left join purchase_value_CTE p
        on c.customer_id = p.customer_id
)
select
    count(*) filter (
        where cancellation_to_purchase_rate >= 100
    ) as customers_cancellation_ge_purchase
    ,count(*) filter (
        where purchase_value is null
    ) as customers_without_observed_purchase
from customer_cancellation_CTE;

-- Transaction items with the highest cancellation value
select
    stock_code
    ,description
    ,count(distinct invoice) as cancelled_invoices
    ,count(*) as cancellation_lines
    ,sum(abs(quantity)) as cancelled_quantity
    ,sum(abs(line_value)) as cancellation_value
from staging.online_retail_prepared
where operation_type = 'cancellation'
group by
    stock_code
    ,description
order by cancellation_value desc
limit 15;

-- Control of the extreme purchase/cancellation pair
select
    invoice
    ,invoice_date
    ,customer_id
    ,stock_code
    ,description
    ,quantity
    ,price
    ,line_value
    ,operation_type
from staging.online_retail_prepared
where stock_code = '23843'
order by invoice_date;

-- Impact of cancellations on customer value ranking
with cancellation_value_CTE as (
    select
        customer_id
        ,sum(abs(line_value)) as cancellation_value
    from staging.online_retail_prepared
    where operation_type = 'cancellation'
      and customer_id is not null
    group by customer_id
),
observed_net_value_CTE as (
    select
        cv.customer_id
        ,cv.total_customer_value as gross_purchase_value
        ,coalesce(c.cancellation_value, 0) as cancellation_value
        ,cv.total_customer_value
         - coalesce(c.cancellation_value, 0) as observed_net_value
    from analytics.customer_value cv
    left join cancellation_value_CTE c
        on cv.customer_id = c.customer_id
),
customer_rank_CTE as (
    select
        customer_id
        ,gross_purchase_value
        ,cancellation_value
        ,observed_net_value
        ,dense_rank() over (
            order by gross_purchase_value desc
        ) as gross_rank
        ,dense_rank() over (
            order by observed_net_value desc
        ) as net_rank
    from observed_net_value_CTE
)
select
    customer_id
    ,gross_purchase_value
    ,cancellation_value
    ,observed_net_value
    ,gross_rank
    ,net_rank
    ,gross_rank - net_rank as rank_change
from customer_rank_CTE
order by gross_rank
limit 20;

-- Seasonality: first observed vs subsequent customer orders
with customer_value_CTE as (
    select
        date_trunc('month', order_date)::date as order_month
        ,count(*) filter (
            where order_number = 1
        ) as first_observed_orders
        ,count(*) filter (
            where order_number > 1
        ) as returning_customer_orders
        ,round(
            sum(order_value) filter (
                where order_number = 1
            )
            ,2
        ) as first_observed_order_value
        ,round(
            sum(order_value) filter (
                where order_number > 1
            )
            ,2
        ) as returning_customer_value
    from analytics.customer_order_sequence
    where order_date < '2011-12-01'
    group by order_month
)
select
    order_month
    ,extract(year from order_month) as order_year
    ,extract(month from order_month) as month_number
    ,first_observed_orders
    ,returning_customer_orders
    ,first_observed_order_value
    ,returning_customer_value
    ,first_observed_orders + returning_customer_orders as total_orders
    ,first_observed_order_value + returning_customer_value as total_order_value
    ,round(
        returning_customer_value * 100.0
        / (first_observed_order_value + returning_customer_value)
        ,2
    ) as returning_value_share
from customer_value_CTE
where extract(year from order_month) in (2010, 2011)
  and extract(month from order_month) <= 11
order by
    month_number
    ,order_year;
