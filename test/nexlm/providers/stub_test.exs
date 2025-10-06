defmodule Nexlm.Providers.StubTest do
  use ExUnit.Case, async: true

  alias Nexlm.Providers.Stub.Store
  alias Nexlm.Error

  defmodule StubServer do
    use GenServer

    def start_link(model) do
      GenServer.start_link(__MODULE__, model)
    end

    def fetch(pid, messages) do
      GenServer.call(pid, {:fetch, messages})
    end

    @impl true
    def init(model) do
      {:ok, %{model: model}}
    end

    @impl true
    def handle_call({:fetch, messages}, _from, state) do
      reply = Nexlm.complete(state.model, messages)
      {:reply, reply, state}
    end
  end

  setup do
    original_registry = Application.get_env(:nexlm, :registry_module)

    case original_registry do
      nil -> Application.delete_env(:nexlm, :registry_module)
      _ -> Application.put_env(:nexlm, :registry_module, Nexlm.Registry)
    end

    Store.clear()

    on_exit(fn ->
      Store.clear()

      case original_registry do
        nil -> Application.delete_env(:nexlm, :registry_module)
        registry -> Application.put_env(:nexlm, :registry_module, registry)
      end
    end)

    :ok
  end

  describe "stub provider integration" do
    test "returns queued response map" do
      Store.put("stub/basic", %{role: "assistant", content: "hi there"})

      assert {:ok, %{role: "assistant", content: "hi there"}} =
               Nexlm.complete("stub/basic", [%{"role" => "user", "content" => "ping"}])
    end

    test "supports queued sequences" do
      Store.put_sequence("stub/sequence", [
        %{role: "assistant", content: "first"},
        %{role: "assistant", content: "second"}
      ])

      assert {:ok, %{content: "first"}} =
               Nexlm.complete("stub/sequence", [%{"role" => "user", "content" => "step"}])

      assert {:ok, %{content: "second"}} =
               Nexlm.complete("stub/sequence", [%{"role" => "user", "content" => "step"}])

      assert {:error, %Error{provider: :stub}} =
               Nexlm.complete("stub/sequence", [%{"role" => "user", "content" => "step"}])
    end

    test "executes function stubs with config and request" do
      parent = self()

      Store.put("stub/capture", fn config, request ->
        send(parent, {:model, config.model})
        send(parent, {:messages, request.messages})

        {:ok, %{role: "assistant", content: "captured"}}
      end)

      assert {:ok, %{content: "captured"}} =
               Nexlm.complete("stub/capture", [%{"role" => "user", "content" => "hello"}])

      assert_receive {:model, "stub/capture"}

      assert_receive {:messages,
                      [
                        %{
                          role: "user",
                          content: "hello",
                          tool_calls: []
                        }
                      ]}
    end

    test "with_stub restores prior state" do
      Store.put("stub/context", %{role: "assistant", content: "original"})

      result =
        Store.with_stub("stub/context", %{role: "assistant", content: "temporary"}, fn ->
          {:ok, %{content: content}} =
            Nexlm.complete("stub/context", [%{"role" => "user", "content" => "hey"}])

          content
        end)

      assert result == "temporary"

      assert {:ok, %{content: "original"}} =
               Nexlm.complete("stub/context", [%{"role" => "user", "content" => "hey"}])
    end

    test "task inherits owner queue" do
      Store.put("stub/async", %{role: "assistant", content: "from owner"})

      task =
        Task.async(fn ->
          Nexlm.complete("stub/async", [
            %{"role" => "user", "content" => "ping"}
          ])
        end)

      assert {:ok, %{content: "from owner"}} = Task.await(task)

      assert {:error, %Error{provider: :stub}} =
               Nexlm.complete("stub/async", [%{"role" => "user", "content" => "ping"}])
    end

    test "gen server inherits owner without extra wiring" do
      Store.put("stub/no_attach", %{role: "assistant", content: "fallback"})

      {:ok, pid} = StubServer.start_link("stub/no_attach")

      assert {:ok, %{content: "fallback"}} =
               StubServer.fetch(pid, [%{"role" => "user", "content" => "hello"}])

      assert {:error, %Error{provider: :stub}} =
               StubServer.fetch(pid, [%{"role" => "user", "content" => "hello"}])
    end
  end
end
