-- Customer Retention & Segmentation Analysis
-- 03. Data preparation and analytical layer

create schema if not exists staging;

-- Remove duplicated source overlap while preserving duplicates that exist
-- only inside a single source file.
create or replace view staging.online_retail_no_source_overlap as
with second_period_without_overlap as (
    select
        invoice
        ,stock_code
        ,description
        ,quantity
        ,invoice_date
        ,price
        ,customer_id
        ,country
    from raw.online_retail_2010_2011

    except all

    select
        invoice
        ,stock_code
        ,description
        ,quantity
        ,invoice_date
        ,price
        ,customer_id
        ,country
    from raw.online_retail_2009_2010
)
select
    '2009-2010' as source_period
    ,invoice
    ,stock_code
    ,description
    ,quantity
    ,invoice_date
    ,price
    ,customer_id
    ,country
from raw.online_retail_2009_2010

union all

select
    '2010-2011' as source_period
    ,invoice
    ,stock_code
    ,description
    ,quantity
    ,invoice_date
    ,price
    ,customer_id
    ,country
from second_period_without_overlap;

-- Convert source text fields to analytical data types
create or replace view staging.online_retail_typed as
select
    source_period
    ,invoice
    ,stock_code
    ,description
    ,quantity::integer as quantity
    ,invoice_date::timestamp as invoice_date
    ,replace(price, ',', '.')::numeric(10,2) as price
    ,customer_id
    ,country
from staging.online_retail_no_source_overlap;

-- Validate converted ranges
select
    min(quantity) as min_quantity
    ,max(quantity) as max_quantity
    ,min(invoice_date) as min_invoice_date
    ,max(invoice_date) as max_invoice_date
    ,min(price) as min_price
    ,max(price) as max_price
from staging.online_retail_typed;

-- Profile non-standard operations before applying analytical rules
select
    count(*) as total_rows
    ,count(*) filter (where invoice like 'C%') as cancelled_rows
    ,count(distinct invoice) filter (where invoice like 'C%') as cancelled_invoices
    ,count(*) filter (where quantity < 0) as negative_quantity_rows
    ,count(*) filter (
        where quantity < 0
          and invoice like 'C%'
    ) as negative_qty_cancelled_rows
    ,count(*) filter (
        where quantity < 0
          and invoice not like 'C%'
    ) as negative_qty_regular_rows
    ,count(*) filter (
        where quantity >= 0
          and invoice like 'C%'
    ) as non_negative_qty_cancelled_rows
    ,count(*) filter (where quantity = 0) as zero_quantity_rows
    ,count(*) filter (where price < 0) as negative_price_rows
    ,count(*) filter (where price = 0) as zero_price_rows
from staging.online_retail_typed;

-- Remove exact duplicates after resolving overlap between the two source files
create or replace view staging.online_retail_deduplicated as
with numbered_rows as (
    select
        source_period
        ,invoice
        ,stock_code
        ,description
        ,quantity
        ,invoice_date
        ,price
        ,customer_id
        ,country
        ,row_number() over (
            partition by
                invoice
                ,stock_code
                ,description
                ,quantity
                ,invoice_date
                ,price
                ,customer_id
                ,country
            order by source_period
        ) as duplicate_row_number
    from staging.online_retail_typed
)
select
    source_period
    ,invoice
    ,stock_code
    ,description
    ,quantity
    ,invoice_date
    ,price
    ,customer_id
    ,country
from numbered_rows
where duplicate_row_number = 1;

-- Classify operations and prepare customer-purchase flag
create or replace view staging.online_retail_prepared as
select
    source_period
    ,invoice
    ,stock_code
    ,description
    ,quantity
    ,invoice_date
    ,price
    ,customer_id
    ,country
    ,case
        when invoice like 'C%'
         and quantity < 0
            then 'cancellation'
        when invoice like 'C%'
         and quantity >= 0
            then 'manual_correction'
        when price < 0
            then 'bad_debt_adjustment'
        when quantity < 0
         and invoice not like 'C%'
            then 'stock_adjustment'
        when price = 0
            then 'zero_price'
        else 'sale'
    end as operation_type
    ,round(quantity * price, 2) as line_value
    ,(
        invoice not like 'C%'
        and quantity > 0
        and price > 0
        and customer_id is not null
    ) as is_customer_purchase
from staging.online_retail_deduplicated;

-- Validate operation classification
select
    operation_type
    ,count(*) as rows_number
    ,sum(line_value) as sum_value
from staging.online_retail_prepared
group by operation_type
order by rows_number desc;

create schema if not exists analytics;

-- Aggregate transaction lines to one row per customer order
create or replace view analytics.customer_orders as
select
    source_period
    ,invoice
    ,customer_id
    ,country
    ,min(invoice_date) as order_date
    ,sum(line_value) as order_value
    ,sum(quantity) as total_items
    ,count(distinct stock_code) as unique_products
    ,count(*) as line_count
from staging.online_retail_prepared
where is_customer_purchase = true
group by
    source_period
    ,invoice
    ,customer_id
    ,country;

-- Final analytical-layer validation
select
    count(*) as order_count
    ,count(distinct customer_id) as unique_customer_count
    ,round(sum(order_value), 2) as total_order_value
    ,min(order_date) as first_order_date
    ,max(order_date) as last_order_date
    ,count(*) filter (where order_value <= 0) as non_positive_order_count
from analytics.customer_orders;
