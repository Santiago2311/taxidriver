defmodule TaxiBeWeb.TaxiAllocationJob do
  use GenServer

  def start_link(request, name) do
    GenServer.start_link(__MODULE__, request, name: name)
  end

  def init(request) do
    Process.send(self(), :step1, [:nosuspend])
    {:ok, %{request: request}}
  end

  def handle_info(:step1, %{request: request}) do
    task =
      Task.async(fn ->
        compute_ride_fare(request)
        |> notify_customer_ride_fare()
      end)

    list_of_taxis = select_candidate_taxis(request) |> Enum.shuffle()
    Task.await(task)

    contacted_taxis = Enum.take(list_of_taxis, 3)

    %{
      "pickup_address" => pickup_address,
      "dropoff_address" => dropoff_address,
      "booking_id" => booking_id
    } = request

    Enum.each(contacted_taxis, fn taxi ->
      TaxiBeWeb.Endpoint.broadcast(
        "driver:" <> taxi.nickname,
        "booking_request",
        %{
          msg: "Viaje de '#{pickup_address}' a '#{dropoff_address}'",
          bookingId: booking_id
        }
      )
    end)

    # timeout de 1.5 minutos (90 segundos)
    time = Process.send_after(self(), :TimeOut, 90_000)

    {:noreply,
     %{
       request: request,
       contacted_taxis: contacted_taxis,
       accepted_taxis: [],
       time: time,
       accepted?: false,
       taxi_arrival_time: nil
     }}
  end

  def handle_info(:TimeOut, %{accepted?: true} = state) do
    {:noreply, state}
  end

  def handle_info(:TimeOut, %{accepted?: false, request: request} = state) do
    %{"username" => customer_username} = request

    TaxiBeWeb.Endpoint.broadcast(
      "customer:" <> customer_username,
      "booking_request",
      %{msg: "Ningún taxi aceptó tu solicitud. Por favor intenta de nuevo."}
    )

    {:noreply, state}
  end

  def compute_ride_fare(request) do
    %{
      "pickup_address" => pickup_address,
      "dropoff_address" => dropoff_address
    } = request

    {request, Enum.random([70, 90, 120])}
  end

  def notify_customer_ride_fare({request, fare}) do
    %{"username" => customer} = request

    TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{
      msg: "Ride fare: #{fare}"
    })
  end

  def handle_cast({:handle_accept, msg}, state) do
    %{request: request, accepted?: already_accepted, time: time} = state
    %{"username" => customer_username} = request

    conductor =
      case msg do
        %{"nickname" => username} -> username
        _ -> "unknown"
      end

    if already_accepted do
      {:noreply, state}
    else
      Process.cancel_timer(time)

      # llegada del taxi en 5 minutos
      taxi_arrival_time = DateTime.utc_now() |> DateTime.add(300, :second)

      TaxiBeWeb.Endpoint.broadcast(
        "customer:" <> customer_username,
        "booking_request",
        %{msg: "Tu taxi está en camino y llegará en 5 minutos"}
      )

      {:noreply,
       %{state |
         accepted?: true,
         accepted_taxis: [conductor],
         taxi_arrival_time: taxi_arrival_time
       }}
    end
  end

  def handle_cast({:handle_reject, msg}, state) do
    {:noreply, state}
  end

  def handle_cast({:handle_cancel, _msg}, %{accepted?: false} = state) do
    %{request: request} = state
    %{"username" => customer_username} = request

    TaxiBeWeb.Endpoint.broadcast(
      "customer:" <> customer_username,
      "booking_request",
      %{msg: "Solicitud cancelada sin cargo."}
    )

    {:noreply, state}
  end

  def handle_cast({:handle_cancel, _msg}, %{accepted?: true, taxi_arrival_time: taxi_arrival_time} = state) do
    %{request: request} = state
    %{"username" => customer_username} = request

    current_time = DateTime.utc_now()
    seconds_until_arrival = DateTime.diff(taxi_arrival_time, current_time)

    if seconds_until_arrival > 180 do
      # más de 3 minutos hasta la llegada del taxi
      # no cargo por cancelación
      TaxiBeWeb.Endpoint.broadcast(
        "customer:" <> customer_username,
        "booking_request",
        %{msg: "Solicitud cancelada sin cargo."}
      )
    else
      # cargo de 20 por cancelación
      TaxiBeWeb.Endpoint.broadcast(
        "customer:" <> customer_username,
        "booking_request",
        %{msg: "Solicitud cancelada. Se aplicará un cargo de 20."}
      )
    end

    {:noreply, state}
  end

  def handle_info(:taxi_arrived, %{accepted?: true, taxi_arrival_time: taxi_arrival_time, request: %{"username" => customer_username}} = state) do
    TaxiBeWeb.Endpoint.broadcast("customer:" <> customer_username, "booking_request", %{msg: "Tu taxi ha llegado. Inicia tu viaje"})
    {:noreply, state}
  end

  def select_candidate_taxis(%{"pickup_address" => _pickup_address}) do
    [
      %{nickname: "frodo", latitude: 19.0319783, longitude: -98.2349368},
      %{nickname: "merry", latitude: 19.0061167, longitude: -98.2697737},
      %{nickname: "samwise", latitude: 19.0092933, longitude: -98.2473716}
    ]
  end
end
