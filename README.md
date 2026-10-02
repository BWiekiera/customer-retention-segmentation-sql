# Customer Retention & Segmentation Analysis

Customer analytics case study focused on behavior, value, retention, lifecycle, reactivation, cancellations, and purchase seasonality, conducted using SQL in PostgreSQL.

## Project Goal

The project focuses on customer-level analysis rather than general sales reporting.

The main objectives were to answer questions such as:

- How many customers place repeat orders?
- How long does it take customers to return?
- How concentrated is gross purchase value across the customer base?
- Which RFM segments have the highest activity, frequency, and share of gross purchase value?
- How does retention change across customer cohorts?
- Which customers are active, at risk, or inactive?
- How often do customers reactivate after a long period of inactivity?
- How do cancellations affect customer value rankings?
- Is there a repeatable seasonal pattern in customer purchases?

## Dataset

The analysis uses the **Online Retail II** dataset from the UCI Machine Learning Repository.

The dataset contains real transaction-level data from a UK-based online retailer and covers the period from **December 2009 to December 2011**.

Key facts:

| Item | Value |
|---|---:|
| Source rows | 1,067,371 |
| Observation period | Dec 2009 – Dec 2011 |
| Source files | 2 |
| Grain | Invoice line |
| Identified customers used in customer analysis | 5,878 |
| Customer orders | 36,969 |
| Gross purchase value used in customer analysis | 17,374,804.25 |

Dataset source: https://archive.ics.uci.edu/dataset/502/online+retail+ii

## Analytical Workflow

The project follows a layered SQL workflow:

```text
raw
  ↓
staging
  ↓
analytics
```

### 1. Raw layer

The original source files were loaded into PostgreSQL without modifying the source data.

The raw layer contains:

- `raw.online_retail_2009_2010`
- `raw.online_retail_2010_2011`
- `raw.online_retail_combined`

### 2. Staging layer

The staging layer was used to:

- remove overlap between the two source periods,
- convert data types,
- inspect data quality,
- deduplicate exact duplicate rows,
- classify transaction types,
- calculate line values,
- flag valid customer purchases.

Main staging views:

- `staging.online_retail_no_source_overlap`
- `staging.online_retail_typed`
- `staging.online_retail_deduplicated`
- `staging.online_retail_prepared`

Transaction types were classified as:

- `sale`
- `cancellation`
- `stock_adjustment`
- `zero_price`
- `bad_debt_adjustment`
- `manual_correction`

### 3. Analytics layer

The analytics layer contains customer-level and order-level views used for the final analysis:

- `analytics.customer_orders`
- `analytics.customer_behavior`
- `analytics.customer_order_sequence`
- `analytics.customer_value`
- `analytics.customer_rfm`
- `analytics.customer_rfm_segments`
- `analytics.customer_cohorts`
- `analytics.customer_cohort_orders`
- `analytics.customer_cohort_retention`
- `analytics.customer_cohort_summary`
- `analytics.customer_lifecycle`

## Data Quality Findings

The initial quality review identified several issues that materially affected the analysis:

| Issue | Result |
|---|---:|
| Missing `customer_id` | 243,007 rows |
| Share of rows without `customer_id` | 22.77% |
| Missing product description | 4,382 rows |
| Overlapping rows between source files | 22,523 |
| Exact duplicate rows removed after overlap handling | 11,812 |

Rows without `customer_id` were retained in the prepared dataset but excluded from customer-level analyses such as RFM, cohorts, retention, and lifecycle analysis.

## Customer Behavior

Customers were classified based on the number of observed orders in the available dataset.

| Customer type | Customers | Share | Orders |
|---|---:|---:|---:|
| Returning | 4,255 | 72.39% | 35,346 |
| One-time | 1,623 | 27.61% | 1,623 |

Returning customers generated approximately **95.61% of all observed customer orders**.

The average time between the first and second observed order was **97.53 days**, while the average gap between all consecutive orders was **51.69 days**.

## Customer Value & Concentration

Customer value was calculated using positive observed purchases.

A strong concentration pattern was identified:

- **1,354 customers**
- **23.04% of the customer base**
- generated **80.01% of gross purchase value**

This is close to, but not exactly, the classical 80/20 relationship.

## RFM Segmentation

RFM metrics were calculated as:

- **Recency** – days since the most recent observed positive order
- **Frequency** – number of observed positive orders
- **Monetary** – gross value of observed positive purchases

`PERCENT_RANK()` was used instead of `NTILE(4)` because it kept customers with identical metric values in the same percentile group.

### Segment Summary

| Segment | Customers | Share | Gross purchase value share |
|---|---:|---:|---:|
| Champion | 611 | 10.39% | 52.49% |
| Loyal customer | 1,280 | 21.78% | 23.12% |
| At risk | 801 | 13.63% | 13.60% |
| Hibernating | 2,148 | 36.54% | 5.59% |
| Potential loyalist | 941 | 16.01% | 5.02% |
| New customer* | 97 | 1.65% | 0.18% |

\* `new_customer` means a customer with one recent order observed in the available dataset. It does not confirm that this was the customer's first-ever purchase from the company.

### Example RFM Logic

```sql
with rfm_percentiles_CTE as
(
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
            and (
                f_percentile >= 0.50
                or m_percentile >= 0.75
            )
            then 'at_risk'
        else 'hibernating'
    end as rfm_segment
from rfm_percentiles_CTE;
```

## Cohort Retention

Customers were assigned to cohorts based on the month of their first observed purchase in the dataset.

Selected results:

| Metric | Result |
|---|---:|
| Average month-1 retention | 21.17% |
| Weighted month-1 retention | 23.15% |
| Highest month-1 retention | 35.29% |
| Lowest month-1 retention | 9.21% |

Weighted retention was used as the more representative overall measure because cohort sizes differ substantially.

`NULL` values were kept distinct from `0%`:

- `NULL` = the cohort has not been observed long enough
- `0%` = the period was observed, but no customers returned

## Customer Lifecycle & Reactivation

Lifecycle thresholds were derived from the distribution of observed gaps between purchases.

The final thresholds were:

| Status | Rule | Share |
|---|---|---:|
| Active | `recency_days <= 70` | 43.55% |
| At risk | `71–147 days` | 12.15% |
| Inactive | `>147 days` | 44.30% |

A reactivation was defined as an order placed after a gap of more than **147 days**.

At least one reactivation was observed for **2,174 customers (36.99%)**.

Among customers currently classified as `at_risk`, **53.08% had already been reactivated at least once**, which suggests a recurring pattern of long purchase gaps for this group.

## Cancellations

Cancellations were analyzed separately from positive purchase behavior.

Key results:

| Metric | Result |
|---|---:|
| Cancelled invoices | 8,291 |
| Customers with cancellations | 2,572 |
| Cancellation value | 1,462,424.18 |
| Cancellation value / sales value | 7.14% |
| Share of cancellation value linked to `customer_id` | 74.18% |

The cancellation analysis showed that rankings based only on gross purchase value can be misleading for individual customers.

Two notable examples:

| Customer | Gross purchase value | Cancellation value | Observed net value | Gross rank | Rank after cancellations |
|---|---:|---:|---:|---:|---:|
| 16446 | 168,472.50 | 168,478.60 | -6.10 | 8 | 5,735 |
| 12346 | 77,556.46 | 77,608.20 | -51.74 | 19 | 5,736 |

Because some cancellations may relate to transactions outside the observation period, the result is described as **observed net value**, not full accounting net customer value.

## Seasonality

Seasonality was compared using the same months in 2010 and 2011 and excluding incomplete December 2011.

The strongest repeatable pattern appeared between September and November.

| Month | Orders 2010 | Orders 2011 | Value 2010 | Value 2011 |
|---|---:|---:|---:|---:|
| September | 1,689 | 1,755 | 829,013.95 | 950,690.20 |
| October | 2,133 | 1,929 | 1,033,112.01 | 1,035,642.45 |
| November | 2,587 | 2,657 | 1,166,460.02 | 1,156,205.61 |

November was the strongest month in both years among the comparable January–November periods.

Because only two comparable yearly cycles are available, this should be treated as a **seasonal signal rather than definitive proof of seasonality**.

## Key SQL Techniques

The project uses:

- CTEs
- conditional aggregation
- `FILTER`
- `CASE`
- `COALESCE`
- `NULLIF`
- `EXCEPT ALL`
- `ROW_NUMBER()`
- `LAG()`
- `DENSE_RANK()`
- `PERCENT_RANK()`
- `FIRST_VALUE()`
- `PERCENTILE_CONT()`
- cumulative window functions
- date arithmetic
- cohort indexing
- data quality validation

## Limitations

### Customer history starts in December 2009

The first purchase visible in the dataset may not be the customer's first-ever purchase from the company.

Therefore:

- `first_purchase_date` should be interpreted as **first observed purchase date**
- cohort assignment is based on the first observed purchase, not confirmed acquisition date
- RFM, lifecycle, and frequency describe behavior within the available observation period

### Missing customer identifiers

22.77% of source rows do not contain `customer_id`, so they cannot be used in customer-level behavioral analysis.

### Cancellations

RFM is based on positive observed purchases. It does not represent full net customer value after cancellations.

A production-level version should use a reliable transaction identifier linking each cancellation to the original sale before recalculating net Monetary values.

## Repository Structure

```text
customer-retention-segmentation-sql/
│
├── README.md
├── .gitignore
│
└── sql/
    ├── 01_database_setup_and_import.sql
    ├── 02_data_quality.sql
    ├── 03_data_preparation.sql
    ├── 04_customer_behavior.sql
    ├── 05_customer_value.sql
    ├── 06_rfm_segmentation.sql
    ├── 07_retention_and_cohort_analysis.sql
    └── 08_cancellations_and_seasonality.sql
```

## SQL File Overview

| File | Purpose |
|---|---|
| `01_database_setup_and_import.sql` | Raw schema, source tables, combined source view |
| `02_data_quality.sql` | Missing values, duplicates, overlap, source validation |
| `03_data_preparation.sql` | Type conversion, deduplication, transaction classification, customer orders |
| `04_customer_behavior.sql` | Repeat customers, order sequence, time between purchases |
| `05_customer_value.sql` | Customer value, ranking, concentration, period comparison |
| `06_rfm_segmentation.sql` | RFM metrics and percentile-based segmentation |
| `07_retention_and_cohort_analysis.sql` | Cohorts, retention, lifecycle, reactivation |
| `08_cancellations_and_seasonality.sql` | Cancellation analysis, ranking impact, seasonality |

## Next Steps

In a production environment, the analysis could be extended with:

- full customer history before December 2009,
- confirmed customer acquisition or registration date,
- enrichment of missing `customer_id`,
- direct cancellation-to-original-sale mapping,
- net Monetary calculation and net RFM segmentation,
- longer history for more robust seasonality analysis.

