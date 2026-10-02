-- Customer Retention & Segmentation Analysis
-- 02. Data quality assessment

-- Missing customer identifiers
select
    count(*) as total_rows
    ,count(*) filter (where customer_id is null) as null_customer_id
    ,round(
        count(*) filter (where customer_id is null) * 100.0 / count(*)
        ,2
    ) as pct_null_customer_id
from raw.online_retail_combined;

-- Completeness of source columns
select
    count(*) as total_rows
    ,count(*) filter (where invoice is null) as null_invoice
    ,count(*) filter (where stock_code is null) as null_stock_code
    ,count(*) filter (where description is null) as null_description
    ,count(*) filter (where quantity is null) as null_quantity
    ,count(*) filter (where invoice_date is null) as null_invoice_date
    ,count(*) filter (where price is null) as null_price
    ,count(*) filter (where customer_id is null) as null_customer_id
    ,count(*) filter (where country is null) as null_country
from raw.online_retail_combined;

-- Records without product description
select
    source_period
    ,count(*) as null_description
    ,count(*) filter (where customer_id is null) as null_description_and_customer_id
from raw.online_retail_combined
where description is null
group by source_period
order by source_period;

select
    count(*) filter (where price = '0') as zero_price_rows
    ,count(*) filter (where price <> '0') as non_zero_price_rows
    ,count(*) filter (where quantity::integer = 0) as zero_quantity_rows
    ,count(*) filter (where quantity::integer > 0) as positive_quantity_rows
    ,count(*) filter (where quantity::integer < 0) as negative_quantity_rows
from raw.online_retail_combined
where description is null;

-- Exact duplicates inside each source period
with duplicate_groups as (
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
        ,count(*) as occurrence_count
    from raw.online_retail_combined
    group by
        source_period
        ,invoice
        ,stock_code
        ,description
        ,quantity
        ,invoice_date
        ,price
        ,customer_id
        ,country
    having count(*) > 1
)
select
    source_period
    ,count(*) as number_duplicate_groups
    ,sum(occurrence_count) as number_duplicate_rows
    ,sum(occurrence_count - 1) as number_extra_duplicate_rows
from duplicate_groups
group by source_period
order by source_period;

-- Date ranges of both source files
select
    source_period
    ,min(invoice_date) as first_date
    ,max(invoice_date) as last_date
from raw.online_retail_combined
group by source_period
order by source_period;

-- Invoice numbers present in both source files
with shared_invoices as (
    select
        invoice
        ,count(distinct source_period) as source_period_count
    from raw.online_retail_combined
    group by invoice
    having count(distinct source_period) = 2
)
select
    count(*) as shared_invoice_count
from shared_invoices;

-- Exact transaction lines present in both source files
with shared_records as (
    select
        invoice
        ,stock_code
        ,description
        ,quantity
        ,invoice_date
        ,price
        ,customer_id
        ,country
        ,count(*) filter (
            where source_period = '2009-2010'
        ) as occurrence_2009_2010
        ,count(*) filter (
            where source_period = '2010-2011'
        ) as occurrence_2010_2011
    from raw.online_retail_combined
    group by
        invoice
        ,stock_code
        ,description
        ,quantity
        ,invoice_date
        ,price
        ,customer_id
        ,country
    having count(distinct source_period) = 2
)
select
    count(*) as shared_record_groups
    ,sum(occurrence_2009_2010) as rows_2009_2010
    ,sum(occurrence_2010_2011) as rows_2010_2011
from shared_records;
