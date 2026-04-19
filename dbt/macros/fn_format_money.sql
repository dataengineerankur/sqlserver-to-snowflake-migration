{% macro fn_format_money(amount_expr) %}
{#
    Replaces: SnowConvertStressDB.dbo.fn_FormatMoney (@amount DECIMAL(18,4)) RETURNS NVARCHAR(50)
    Original: N'$' + CONVERT(NVARCHAR(50), CAST(@amount AS MONEY), 1)  -- adds comma separators

    Snowflake equivalent: TO_VARCHAR with format mask.
    Usage in models: {{ fn_format_money('total_amount') }}
              or   {{ fn_format_money('COALESCE(SUM(x), 0)') }}
#}
    '$' || TO_VARCHAR({{ amount_expr }}, '999,999,999,990.00')
{% endmacro %}
