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

    # select closest taxi
    taxi = hd(list_of_taxis)

    %{
      "pickup_address" => pickup_address,
      "dropoff_address" => dropoff_address,
      "booking_id" => booking_id
    } = request

    TaxiBeWeb.Endpoint.broadcast(
      "driver:" <> taxi.nickname,
      "booking_request",
      %{
        msg: "Viaje de '#{pickup_address}' a '#{dropoff_address}'",
        bookingId: booking_id
      }
    )

    timer = Process.send_after(self(), TimeOut, 10_000)
    {:noreply, %{request: request, contacted_taxi: taxi, candidates: tl(list_of_taxis)}}
  end

  def handle_info(TimeOut, state) do
    auxiliary(state)
  end

  def compute_ride_fare(request) do
    %{
      "pickup_address" => pickup_address,
      "dropoff_address" => dropoff_address
    } = request

    {request, Enum.random([34, 70, 90, 120, 150, 220, 500])}
  end

  def notify_customer_ride_fare({request, fare}) do
    %{"username" => customer} = request

    TaxiBeWeb.Endpoint.broadcast("customer:" <> customer, "booking_request", %{
      msg: "Ride fare: #{fare}"
    })
  end

  def handle_cast({:handle_accept, msg}, state) do
    %{request: request} = state
    %{"username" => customer_username} = request
    IO.puts("Must process accept")
    IO.puts("The client is " <> customer_username)
    IO.inspect(msg)
    IO.inspect(request)

    TaxiBeWeb.Endpoint.broadcast("customer:" <> customer_username, "booking_request", %{
      msg: "Tu taxi esta en camino y llegara en 5 minutos"
    })

    {:noreply, state}
  end

  def handle_cast({:handle_reject, msg}, state) do
    auxiliary(state)
    {:noreply, state}
  end

  def auxiliary(%{request: request, candidates: list_of_taxis} = state) do
    case list_of_taxis do
      [] ->
        {:noreply, state}

      [n_taxi | leftover] ->
        %{
          "pickup_address" => pickup_address,
          "dropoff_address" => dropoff_address,
          "booking_id" => booking_id
        } = request

        TaxiBeWeb.Endpoint.broadcast(
          "driver:" <> n_taxi.nickname,
          "booking_request",
          %{
            msg: "Viaje de '#{pickup_address}' a '#{dropoff_address}'",
            bookingId: booking_id
          }
        )

        if leftover != [] do
          Process.send_after(self(), TimeOut, 10_000)
        end

        {:noreply, %{request: request, contacted_taxi: n_taxi, candidates: leftover}}
    end
  end

  def select_candidate_taxis(%{"pickup_address" => _pickup_address}) do
    [
      %{nickname: "frodo", latitude: 19.0319783, longitude: -98.2349368},
      %{nickname: "merry", latitude: 19.0061167, longitude: -98.2697737},
      %{nickname: "samwise", latitude: 19.0092933, longitude: -98.2473716}
    ]
  end
end
