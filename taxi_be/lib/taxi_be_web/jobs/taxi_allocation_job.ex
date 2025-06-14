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

    time = Process.send_after(self(), TimeOut, 90_000)

    {:noreply,
     %{
       request: request,
       contacted_taxis: contacted_taxis,
       accepted_taxis: [],
       time: time,
       accepted?: false
     }}
  end

  def handle_info(TimeOut, %{accepted?: true} = state) do
    {:noreply, state}
  end

  def handle_info(TimeOut, %{accepted?: false, request: request} = state) do
    %{"username" => customer_username} = request

    TaxiBeWeb.Endpoint.broadcast(
      "customer:" <> customer_username,
      "booking_request",
      %{msg: "Por el momento no se encuentra disponible ninguna unidad"}
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

      TaxiBeWeb.Endpoint.broadcast(
        "customer:" <> customer_username,
        "booking_request",
        %{msg: "Tu taxi está en camino y llegará en 5 minutos"}
      )

      {:noreply, %{state | accepted?: true, accepted_taxis: [conductor]}}
    end
  end

  def handle_cast({:handle_reject, msg}, state) do
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
