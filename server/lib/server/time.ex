defmodule Server.Time do
  @moduledoc "Shared time helpers for timestamping trace/console entries."

  @doc "Local wall-clock time as a zero-padded `HH:MM:SS` string."
  def hms do
    {_, {h, m, s}} = :calendar.local_time()
    :io_lib.format("~2..0b:~2..0b:~2..0b", [h, m, s]) |> to_string()
  end
end
