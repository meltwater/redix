defmodule Redix.StartOptions do
  @moduledoc false

  @default_log_options [
    disconnection: :error,
    failed_connection: :error,
    reconnection: :info
  ]

  @default_sentinel_options [
    timeout: 500,
    socket_opts: [],
    ssl: false
  ]

  @default_options [
    socket_opts: [],
    ssl: false,
    sync_connect: false,
    backoff_initial: 500,
    backoff_max: 30000,
    log: @default_log_options,
    exit_on_disconnection: false
  ]

  @allowed_options [:host, :port, :database, :password, :name, :sentinel] ++
                     Keyword.keys(@default_options)

  def sanitize(options) when is_list(options) do
    @default_options
    |> Keyword.merge(options)
    |> assert_only_known_options()
    |> maybe_sanitize_sentinel_opts()
    |> maybe_sanitize_host_and_port()
    |> fill_default_log_options()
  end

  defp assert_only_known_options(options) do
    Enum.each(options, fn {key, _value} ->
      unless key in @allowed_options do
        raise ArgumentError, "unknown option: #{inspect(key)}"
      end
    end)

    options
  end

  defp fill_default_log_options(options) do
    Keyword.update!(options, :log, &Keyword.merge(@default_log_options, &1))
  end

  defp maybe_sanitize_sentinel_opts(options) do
    case Keyword.fetch(options, :sentinel) do
      {:ok, sentinel_opts} ->
        Keyword.put(options, :sentinel, sanitize_sentinel_opts(sentinel_opts))

      :error ->
        options
    end
  end

  defp sanitize_sentinel_opts(sentinel_opts) do
    case Keyword.fetch(sentinel_opts, :sentinels) do
      {:ok, sentinels} when is_list(sentinels) and sentinels != [] ->
        :ok

      {:ok, sentinels} ->
        raise ArgumentError,
              "the :sentinels option inside :sentinel must be a non-empty list, got: " <>
                inspect(sentinels)

      :error ->
        raise ArgumentError, "the :sentinels option is required inside :sentinel"
    end

    unless Keyword.has_key?(sentinel_opts, :group) do
      raise ArgumentError, "the :group option is required inside :sentinel"
    end

    if Keyword.has_key?(sentinel_opts, :host) or Keyword.has_key?(sentinel_opts, :port) do
      raise ArgumentError, ":host or :port can't be passed as option if :sentinel is used"
    end

    sentinel_opts =
      Keyword.update!(sentinel_opts, :sentinels, fn sentinels ->
        Enum.map(sentinels, fn
          {host, port} when is_binary(host) and is_integer(port) ->
            {to_charlist(host), port}

          other ->
            raise ArgumentError,
                  "sentinel addresses must be in the form {host, port} where " <>
                    "host is a binary and port is an integer, got: #{inspect(other)}"
        end)
      end)

    Keyword.merge(@default_sentinel_options, sentinel_opts)
  end

  defp maybe_sanitize_host_and_port(options) do
    if Keyword.has_key?(options, :sentinel) do
      options
    else
      {host, port} =
        case {Keyword.get(options, :host, "localhost"), Keyword.fetch(options, :port)} do
          {{:local, _unix_socket_path}, {:ok, port}} when port != 0 ->
            raise ArgumentError,
                  "when using Unix domain sockets, the port must be 0, got: #{inspect(port)}"

          {{:local, _unix_socket_path} = host, :error} ->
            {host, 0}

          {_host, {:ok, port}} when not is_integer(port) ->
            raise ArgumentError,
                  "expected an integer as the value of the :port option, got: #{inspect(port)}"

          {host, {:ok, port}} when is_binary(host) ->
            {String.to_charlist(host), port}

          {host, :error} when is_binary(host) ->
            {String.to_charlist(host), 6379}
        end

      Keyword.merge(options, host: host, port: port)
    end
  end
end
