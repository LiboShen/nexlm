defmodule Nexlm.Providers.StubTest do
  use ExUnit.Case, async: true

  alias Nexlm.Providers.Stub.Store
  alias Nexlm.Error

  setup do
    Store.clear()
    on_exit(&Store.clear/0)
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
  end
end
