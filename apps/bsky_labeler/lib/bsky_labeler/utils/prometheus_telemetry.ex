defmodule BskyLabeler.Utils.PrometheusTelemetry do
  @moduledoc """
  Macros for attaching Prometheus to `:telemetry` events.
  """

  defmacro metric(
             [
               {:name, name},
               {:event, event},
               {:type, type},
               {:help, help} | other_options
             ],
             do: do_block
           ) do
    label_ids = other_options[:labels] || []

    case_clauses =
      Enum.map(
        do_block,
        fn {:->, arrow_meta, [[arrow_left_1, arrow_left_2], arrow_right]} ->
          {:->, arrow_meta, [[{arrow_left_1, arrow_left_2}], arrow_right]}
        end
      )

    quote do
      @declare_metric {unquote(name), unquote(type), unquote(help), unquote(label_ids),
                       unquote(other_options)}
      @attach_telemetry {unquote(event), unquote(name)}
      def telemetry_handler(unquote(event), meas, meta, unquote(name)) do
        result =
          case {meas, meta} do
            unquote(case_clauses)
          end

        # In a different function to work-around type warnings
        command_tuple_to_observe(result, unquote(name), unquote(type))
      end
    end
  end

  defmacro __using__(_) do
    module = __MODULE__

    quote do
      Module.register_attribute(__MODULE__, :declare_metric, accumulate: true)
      Module.register_attribute(__MODULE__, :attach_telemetry, accumulate: true)
      @before_compile BskyLabeler.Utils.PrometheusTelemetry.Helper

      import unquote(module), only: [metric: 2]

      defp command_tuple_to_observe(result, name, type) do
        case result do
          {:increment, labels} ->
            Prometheus.Metric.Counter.inc(
              name: name,
              labels: labels
            )

          {:increment, count, labels} ->
            Prometheus.Metric.Counter.inc(
              [name: name, labels: labels],
              count
            )

          {:observe, measure, labels} when type == :histogram ->
            Prometheus.Metric.Histogram.observe(
              [name: name, labels: labels],
              measure
            )

          {:observe, measure, labels} when type == :summary ->
            Prometheus.Metric.Summary.observe(
              [name: name, labels: labels],
              measure
            )

          {:set, value, labels} ->
            Prometheus.Metric.Gauge.set([name: name, labels: labels], value)
        end
      end
    end
  end
end

defmodule BskyLabeler.Utils.PrometheusTelemetry.Helper do
  @moduledoc false
  defmacro __before_compile__(_env) do
    quote do
      def attach_telemetry do
        Enum.each(@attach_telemetry, fn {event, prom_name} ->
          handler_id = "prometheus-#{prom_name}"
          :ok = :telemetry.attach(handler_id, event, &__MODULE__.telemetry_handler/4, prom_name)
        end)
      end

      def setup_prometheus do
        Enum.each(@declare_metric, fn
          {name, type, help, labels, other_options} ->
            module =
              case type do
                :counter -> Prometheus.Metric.Counter
                :histogram -> Prometheus.Metric.Histogram
                :gauge -> Prometheus.Metric.Gauge
                :summary -> Prometheus.Metric.Summary
              end

            module.new(
              [name: name, help: help, labels: labels] ++
                other_options
            )
        end)
      end
    end
  end
end
