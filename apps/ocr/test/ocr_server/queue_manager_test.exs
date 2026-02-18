defmodule OcrServer.QueueManagerTest do
  use ExUnit.Case, async: true

  alias OcrServer.QueueManager
  import System, only: [monotonic_time: 1]
  import Process, only: [sleep: 1]

  defp start(max_current) do
    start_link_supervised!({QueueManager, max_current: max_current})
  end

  test "one instance" do
    m = start(1)

    assert {:ok, :foo} == QueueManager.command(m, fn -> :foo end, 1)
  end

  test "multiple instances leq than max_current" do
    m = start(100)

    tasks =
      for _ <- 1..100 do
        Task.async(fn ->
          QueueManager.command(m, fn -> Process.sleep(100) end, 150)
        end)
      end

    results = Task.await_many(tasks, 190)
    assert Enum.all?(results, &(&1 == {:ok, :ok}))
  end

  test "multiple instances more than max_current" do
    m = start(30)

    start = monotonic_time(:millisecond)

    tasks =
      for _ <- 1..100 do
        Task.async(fn ->
          QueueManager.command(m, fn -> Process.sleep(100) end, 150)
        end)
      end

    results = Task.await_many(tasks, 490)
    end_ = monotonic_time(:millisecond)
    assert Enum.all?(results, &(&1 == {:ok, :ok}))

    dur = end_ - start
    assert dur in 400..490
  end

  test "queue exactly max" do
    m = start(1)

    _t1 =
      Task.async(fn ->
        QueueManager.command(m, fn -> Process.sleep(100) end, 50)
      end)

    t2 = Task.async(fn -> QueueManager.command(m, fn -> :foo end, 1) end)

    assert {:ok, :foo} == Task.await(t2, 150)
  end

  test "queue full" do
    m = start(1)

    _t1 =
      Task.async(fn ->
        QueueManager.command(m, fn -> Process.sleep(100) end, 50)
      end)

    _t2 =
      Task.async(fn ->
        QueueManager.command(m, fn -> Process.sleep(100) end, 50)
      end)

    t3 = Task.async(fn -> QueueManager.command(m, fn -> :foo end, 1) end)

    assert :queue_full == Task.await(t3, 90)
  end

  test "is FIFO" do
    m = start(3)

    this = self()

    tasks =
      for i <- 1..10 do
        t =
          Task.async(fn ->
            send(this, :task_running)

            QueueManager.command(
              m,
              fn ->
                Process.sleep(100)
                send(this, {:task_result, i})
              end,
              450
            )
          end)

        # ensure task is scheduled
        receive do
          :task_running -> nil
        end

        t
      end

    Task.await_many(tasks, 490)

    results = receive_all(:task_result, 10)

    [results1, results2, results3, results4] = Enum.chunk_every(results, 3)

    # Chunks are in order, bar scheduling of tasks that fire closely.

    # First chunk is in order as it is not queued
    assert Enum.all?(results1, &(&1 in 1..3)),
           inspect(results1, charlists: :as_lists)

    assert Enum.all?(results2, &(&1 in 4..6)),
           inspect(results2, charlists: :as_lists)

    assert Enum.all?(results3, &(&1 in 7..9)),
           inspect(results3, charlists: :as_lists)

    assert results4 === [10]
  end

  test "next command given pass when function throws" do
    m = start(1)

    try do
      QueueManager.command(m, fn -> throw(:foo) end, 1)
    catch
      :foo -> nil
    end

    assert {:ok, :bar} == QueueManager.command(m, fn -> :bar end, 1)
  end

  test "next command given pass when caller exits" do
    m = start(1)
    this = self()

    spawn(fn ->
      QueueManager.command(
        m,
        fn ->
          send(this, :spawned)
          Process.exit(self(), :kill)
        end,
        1
      )
    end)

    receive do
      :spawned -> nil
    end

    assert {:ok, :bar} == QueueManager.command(m, fn -> :bar end, 1)
  end

  test "caller removed from queue after exit" do
    m = start(1)

    t1 =
      Task.async(fn -> QueueManager.command(m, fn -> sleep(100) end, 5) end)

    sleep(10)

    p2 =
      spawn(fn -> QueueManager.command(m, fn -> sleep(100) end, 5) end)

    sleep(10)

    t3 = Task.async(fn -> QueueManager.command(m, fn -> :ok end, 5) end)

    Process.exit(p2, :kill)

    assert [{:ok, :ok}, {:ok, :ok}] == Task.await_many([t1, t3], 190)
  end

  defp receive_all(_tag, 0 = _count) do
    []
  end

  defp receive_all(tag, count) do
    receive do
      {^tag, value} ->
        [value | receive_all(tag, count - 1)]
    end
  end
end
