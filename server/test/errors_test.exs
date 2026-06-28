defmodule Server.ErrorsTest do
  use ExUnit.Case, async: true

  alias Server.Errors
  alias Server.Schema.AppError

  test "maps known atoms to friendly copy with no detail" do
    assert %AppError{message: msg, detail: nil} = Errors.humanize(:no_enabled_rtp)
    assert msg =~ "trace pattern"
    assert %AppError{detail: nil} = Errors.humanize(:unreachable)
  end

  test "unknown atom still yields a message" do
    assert %AppError{message: "Error: " <> _, detail: nil} = Errors.humanize(:boom)
  end

  test "multi-line string keeps first line as message, full text as detail" do
    assert %AppError{message: "** (RuntimeError) bad", detail: detail} =
             Errors.humanize("** (RuntimeError) bad\n  at foo:1")

    assert detail =~ "at foo:1"
  end

  test "single-line string has nil detail" do
    assert %AppError{message: "boom", detail: nil} = Errors.humanize("boom")
  end
end
