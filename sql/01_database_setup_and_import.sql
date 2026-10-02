-- Customer Retention & Segmentation Analysis
-- 01. Database setup and source data structure

create schema if not exists raw;

create table if not exists raw.online_retail_2009_2010 (
    invoice text
    ,stock_code text
    ,description text
    ,quantity text
    ,invoice_date text
    ,price text
    ,customer_id text
    ,country text
);

create table if not exists raw.online_retail_2010_2011 (
    invoice text
    ,stock_code text
    ,description text
    ,quantity text
    ,invoice_date text
    ,price text
    ,customer_id text
    ,country text
);

-- Source files were imported as CSV files in pgAdmin.
-- The raw layer intentionally preserves the source data without cleaning.

-- Import validation
select
    count(*) as row_count
from raw.online_retail_2009_2010;

select
    count(*) as row_count
from raw.online_retail_2010_2011;

-- Combine both source periods without removing duplicates
create or replace view raw.online_retail_combined as
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
from raw.online_retail_2010_2011;

-- Combined source validation
select
    source_period
    ,count(*) as row_count
from raw.online_retail_combined
group by source_period
order by source_period;
