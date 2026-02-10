defmodule BskyLabeler.ConfigManager do
  @moduledoc """
  Stores mutable config for the pipeline.
  """

  use Agent

  @doc """
  Accepts `:name` option; the rest are stored in the process.
  """
  def start_link(opts) do
    {agent_opts, config} = Keyword.split(opts, [:name])

    Agent.start_link(fn -> config end, agent_opts)
  end

  @doc """
  Gets the configuration by key.
  """
  def get(cm, key) do
    Agent.get(cm, & &1[key])
  end

  @doc """
  Sets a configuration value by key.
  """
  def set(cm, key, value) do
    Agent.update(cm, &Keyword.put(&1, key, value))
  end
end
