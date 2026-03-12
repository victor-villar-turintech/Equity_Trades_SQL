# PLAN_SNOWFLAKE.md

# Snowflake Translation and Migration Plan

This document is the second-stage execution plan to be used **after** the original consolidation, dependency, validation, and performance plan has been completed. Its purpose is to take the outputs of the original plan and translate the resulting schema, SQL, validation logic, and performance benchmarking framework into **Snowflake-compatible implementations**.

This plan assumes that Artemis has already:
- identified the dimension tables that can be consolidated
- mapped all downstream dependencies
- designed the new consolidated dimension
- refactored downstream logic conceptually or physically
- produced before-versus-after validation SQL
- produced benchmark SQL and performance-comparison logic

The role of this second-stage plan is to convert that completed design and SQL output into a form that executes correctly, efficiently, and idiomatically on Snowflake.

---

## Objective

Artemis must translate the outputs of the original plan into Snowflake-compatible DDL, DML, transformation SQL, validation SQL, and performance measurement SQL/scripts, while preserving semantic equivalence and ensuring the resulting implementation is operationally safe on Snowflake.

The target outcome is a fully Snowflake-ready implementation of:
1. the new consolidated dimension table
2. the downstream fact and mart rewrites
3. the validation suite
4. the ETL/performance benchmark suite

---

## Scope

This plan applies to all SQL artifacts and database objects generated or modified by the original plan, including but not limited to:

- consolidated dimension DDL
- dimension population SQL
- downstream fact-table rewrites
- downstream mart-table rewrites
- staging/intermediate model rewrites
- views
- validation queries
- benchmark queries
- ETL timing or execution measurement logic
- rollback SQL where applicable

This plan also applies to all old SQL patterns inherited from non-Snowflake environments that require translation.

---

## Operating principles

- Do not perform a superficial syntax substitution only. Translate for **correctness**, **semantic equivalence**, and **Snowflake execution behavior**.
- Preserve business meaning exactly.
- Preserve row grain exactly.
- Preserve key semantics exactly.
- Preserve before-versus-after validation logic exactly, unless a Snowflake-specific equivalent must be used.
- Prefer native Snowflake constructs where they improve clarity or performance without changing semantics.
- Document every place where dialect translation affects behavior, especially around null handling, timestamps, string comparison, hashing, merge logic, temp objects, and performance measurement.
- Do not claim success until translated SQL is syntactically valid and logically equivalent on Snowflake.

---

## Inputs required

Artemis must consume the output of the original plan as structured input. At minimum, the following must be available:

1. The list of original source dimensions selected for consolidation
2. The DDL design for the new consolidated dimension
3. The population logic for the new consolidated dimension
4. The full downstream dependency inventory
5. The rewritten downstream join/key mappings
6. The validation SQL suite
7. The benchmark/performance SQL suite
8. Any existing SQL engine assumptions from the current implementation
9. Any benchmark runner or orchestration scripts created in the original plan

If any of these are missing, Artemis must explicitly state what is missing before attempting a partial Snowflake translation.

---

## Required outputs

Artemis must produce all of the following:

### A. Snowflake compatibility assessment
### B. Snowflake object design
### C. Snowflake DDL translation
### D. Snowflake DML and transformation translation
### E. Snowflake downstream rewrite translation
### F. Snowflake validation suite
### G. Snowflake benchmark and performance suite
### H. Snowflake deployment order
### I. Snowflake rollback and cutover plan

---

# A. Snowflake compatibility assessment

Artemis must inspect the SQL produced by the original plan and classify every statement into one of these categories:

1. Already Snowflake-compatible
2. Requires minor syntax translation
3. Requires semantic translation
4. Requires redesign because the original engine behavior does not map directly to Snowflake

For each SQL artifact, Artemis must document:
- artifact name
- original purpose
- source SQL dialect or assumed dialect
- Snowflake compatibility status
- required changes
- semantic risks

Artemis must specifically inspect for dialect-sensitive constructs such as:
- temporary table syntax
- identity/sequence syntax
- merge/upsert syntax
- create table as select patterns
- date arithmetic
- timestamp conversion
- interval expressions
- boolean handling
- string concatenation
- null-safe comparisons
- hash/checksum functions
- explain plan usage
- index assumptions
- statistics assumptions
- optimizer hints
- materialized view assumptions
- transaction semantics
- update/delete behavior
- procedural SQL blocks
- variables and session parameters

Artemis must explicitly identify any places where the original SQL assumes:
- B-tree indexes
- clustered indexes
- explicit physical indexing
- optimizer hints from another engine
- database-specific CTE/materialization behavior
- engine-specific explain output
- dbt or orchestration features that behave differently on Snowflake

---

# B. Snowflake object design

Artemis must define the physical Snowflake object strategy for all migrated artifacts.

For each object, Artemis must decide and justify whether it should be:
- permanent table
- transient table
- temporary table
- view
- materialized view
- dynamic table, if relevant and appropriate

For the new consolidated dimension, Artemis must specify:
- object name
- database
- schema
- retention expectations
- whether transient is acceptable
- whether clustering is required
- whether search optimization is relevant
- whether streams/tasks are part of the load design
- whether the object must support full refresh or incremental maintenance

For each rewritten downstream object, Artemis must specify:
- target Snowflake object type
- dependency order
- whether it is rebuilt or incrementally updated
- whether it needs zero-copy clone safety for release validation
- whether it should be dual-run during migration

---

# C. Snowflake DDL translation

Artemis must translate all new and modified schema definitions into valid Snowflake DDL.

For every table, provide:
- `CREATE OR REPLACE` or safe deployment alternative
- complete column definitions
- data type mapping
- nullable/not-null expectations
- surrogate key strategy
- comments if appropriate
- constraints if useful for documentation, even if not enforced physically
- clustering strategy if justified

Artemis must explicitly handle type mapping from the original design into Snowflake equivalents, including:
- integer types
- decimal/numeric types
- string/varchar types
- boolean types
- date
- timestamp_ntz / timestamp_ltz / timestamp_tz
- floating-point types

Artemis must choose the correct Snowflake timestamp type based on the business meaning of the source fields. If time zone semantics are ambiguous, Artemis must state the ambiguity and propose a standard.

For the consolidated dimension DDL, Artemis must:
1. produce the full Snowflake `CREATE TABLE` statement
2. include the legacy source keys if required for traceability
3. ensure the table grain is preserved
4. ensure data type choices are compatible with downstream joins and validations

If the original design used sequences, identity, or generated surrogate keys, Artemis must translate them into Snowflake-safe mechanisms and document the choice.

---

# D. Snowflake DML and transformation translation

Artemis must translate all load and transformation logic into Snowflake-compatible SQL.

This includes:
- insert-select logic
- merge logic
- update logic
- incremental load logic
- full-refresh logic
- de-duplication logic
- conformance logic
- null handling
- timestamp coercion
- join rewrites
- key remapping

For the new consolidated dimension, Artemis must provide:
1. the Snowflake SQL to populate the unified dimension
2. the exact join logic across the original dimensions
3. uniqueness checks
4. duplicate prevention logic
5. referential coverage checks against the fact table

Artemis must determine whether the Snowflake implementation should use:
- `INSERT INTO ... SELECT`
- `CREATE TABLE AS SELECT`
- `MERGE`
- staging tables followed by controlled swap/cutover
- streams/tasks for automation if appropriate

Artemis must explicitly translate any non-Snowflake constructs such as:
- `UPSERT`
- vendor-specific `MERGE`
- `TOP`
- engine-specific date functions
- engine-specific hash/checksum functions
- nonstandard casting syntax
- engine-specific temp table semantics

---

# E. Snowflake downstream rewrite translation

Artemis must take the downstream migration plan from the first document and express every impacted downstream object in Snowflake-compatible SQL.

For each impacted fact/intermediate/mart object, Artemis must provide:
- original logical dependency pattern
- new dependency pattern
- translated Snowflake SQL
- notes on semantic equivalence
- notes on any Snowflake-specific rewrites for performance or correctness

Where the original downstream logic joined multiple security-related dimensions, Artemis must translate the refactored Snowflake version so that it joins only the new consolidated dimension for those attributes.

Where unrelated dimensions remain in use, Artemis must leave them unchanged except for required Snowflake syntax translation.

If any object should be introduced in dual-run mode, Artemis must define:
- the Snowflake object names for legacy and new versions
- the coexistence strategy
- how validation will compare them
- how cutover will occur

---

# F. Snowflake validation suite

Artemis must translate the full validation framework into Snowflake SQL.

The goal is to prove that the outputs of the migrated Snowflake implementation are semantically identical to the pre-migration outputs.

For each impacted downstream object, Artemis must produce Snowflake queries that validate:
- row count equality
- business key uniqueness equality
- null count equality on important fields
- aggregate equality on important measures
- row-level mismatch detection where feasible
- dimensional attribute equivalence
- referential completeness

The validation framework must support:
- before-versus-after comparisons
- legacy-versus-new object comparisons
- mismatch surfacing
- pass/fail interpretation

Artemis must choose Snowflake-compatible implementations for:
- row-hash comparisons
- checksum patterns
- null-safe comparisons
- timestamp normalization for comparison
- string normalization if required

For every validation query, Artemis must include:
- objective of the query
- expected result when migration is correct
- what a failure implies
- whether the query is safe for large-scale execution or should be sampled/partitioned

Artemis must also generate validation SQL that proves downstream objects no longer depend on the fragmented set of security-related dimensions once cutover is complete.

---

# G. Snowflake benchmark and performance suite

Artemis must convert the performance comparison framework into Snowflake-compatible benchmark logic.

The benchmark must compare:
1. original multi-dimension logic
2. refactored consolidated-dimension logic

Artemis must produce a benchmark suite that can be run fairly on Snowflake and must define:
- test objects
- test SQL
- repetition strategy
- warm/cold cache assumptions if applicable
- warehouse size/class
- execution conditions
- measurement method

Artemis must produce Snowflake-compatible methods to capture:
- elapsed execution time
- query history identifiers if useful
- scanned bytes if available
- partitions/micro-partitions touched if available
- rows produced
- repeated run averages
- explain plan or profile references where available

Artemis must explicitly use Snowflake-native observability where appropriate, such as:
- query history
- query profile
- account usage or information schema views where available

Artemis must not assume index-driven performance behavior, because Snowflake does not optimize in the same way as traditional row-store engines.

Artemis must explain benchmark outcomes in Snowflake terms, for example:
- reduced join complexity
- fewer intermediate expansions
- improved pruning opportunities
- lower scanned data
- simpler aggregation path
- reduced compute time

---

# H. Snowflake deployment order

Artemis must provide the deployment sequence for the Snowflake migration.

At minimum the order must include:
1. create or stage the new consolidated dimension
2. populate and validate the new dimension
3. build translated downstream objects in parallel or side-by-side
4. execute the validation suite
5. execute the benchmark suite
6. compare results
7. approve or reject cutover
8. switch downstream dependencies to the new Snowflake objects
9. deprecate or retain legacy objects per rollback policy

Artemis must produce the deployment plan in a deterministic order with explicit dependencies.

Where appropriate, Artemis should recommend use of:
- staging schema
- validation schema
- zero-copy clones
- controlled object swaps
- separate warehouses for benchmark repeatability

---

# I. Snowflake rollback and cutover plan

Artemis must define a Snowflake-specific rollback strategy.

The rollback plan must include:
- what objects remain untouched until validation passes
- which objects are promoted only at cutover
- how to restore the prior state if validation fails
- whether zero-copy clone can be used for protection
- how to preserve evidence of failed validation
- how to rerun benchmarks after rollback

Artemis must define:
- go/no-go criteria
- exact cutover prerequisites
- exact rollback triggers
- post-cutover validation
- post-cutover monitoring steps

---

# Required execution sequence

Artemis must follow this order:

1. Read the output artifacts from the original plan.
2. Inventory all SQL and schema artifacts that must be translated to Snowflake.
3. Perform a compatibility assessment for each artifact.
4. Translate the consolidated dimension DDL into Snowflake.
5. Translate the dimension load/transformation logic into Snowflake.
6. Translate all downstream impacted objects into Snowflake.
7. Translate the validation suite into Snowflake.
8. Translate the benchmark/performance suite into Snowflake.
9. Define the deployment, cutover, and rollback strategy for Snowflake.
10. Produce a final Snowflake-ready implementation package.

---

# Expected output sections

Artemis must return the result in the following sections:

1. Input artifacts consumed from the original plan
2. Snowflake compatibility assessment
3. Snowflake DDL for the consolidated dimension
4. Snowflake DML/load logic for the consolidated dimension
5. Snowflake translation of downstream fact/intermediate/mart rewrites
6. Snowflake validation SQL suite
7. Snowflake benchmark/performance suite
8. Snowflake deployment order
9. Snowflake rollback and cutover plan
10. Final readiness assessment

---

# Quality bar

The output is only acceptable if:
- every required SQL artifact from the original plan is addressed
- all translated SQL is Snowflake-compatible
- semantic equivalence is preserved
- validation logic is concrete and executable in Snowflake
- performance benchmarking is concrete and measurable in Snowflake
- deployment order is explicit
- rollback steps are explicit
- all unresolved engine-specific risks are clearly identified

---

# Important instruction

Do not respond with generic advice about Snowflake migration. Produce an implementation-ready Snowflake translation plan based specifically on the output of the original plan. The result must be executable, testable, and suitable for direct handoff to a coding or migration agent.
