import React, {useEffect, useState} from 'react';
import Button from '@mui/material/Button'
import socket from '../services/taxi_socket';
import { TextField } from '@mui/material';

function Customer(props) {
  let [pickupAddress, setPickupAddress] = useState("Tecnologico de Monterrey, campus Puebla, Mexico");
  let [dropOffAddress, setDropOffAddress] = useState("Triangulo Las Animas, Puebla, Mexico");
  let [msg, setMsg] = useState("");
  let [msg2, setMsg2] = useState("");
  let [bookingId, setBookingId] = useState(null);

  useEffect(() => {
    let channel = socket.channel("customer:" + props.username, {token: "123"});
    channel.on("greetings", data => console.log(data));
    channel.on("booking_request", data => {
      console.log("Received", data);
      setMsg2(data.msg);
    });
    channel.join()
    .receive("OK", resp => console.log("Joined successfully", resp))
    .receive("error", resp => console.error("Unable to join", resp));

    return () => {
      channel.leave();
    };
  },[props.username]);

  let submit = () => {
    setMsg("");

    fetch(`http://localhost:4000/api/bookings`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        pickup_address: pickupAddress, 
        dropoff_address: dropOffAddress, 
        username: props.username
      })
    })
    .then(resp => resp.json())
    .then(data => {
      setBookingId(data.id);
      setMsg(data.msg);
    })
    .catch(error => {
      console.error('Error:', error);
      setMsg('Error processing request');
    });
  };

  let cancel = () => {
    if (!bookingId) return;
    setMsg("");
    setMsg2("");

    fetch(`http://localhost:4000/api/bookings/${bookingId}`, {
      method: 'POST',
      headers: {'Content-Type': 'application/json'},
      body: JSON.stringify({
        action: 'cancel',
        username: props.username,
        id: bookingId
      })
    }).then(resp => resp.json()).then(data => {

      setMsg(data.msg);
      setBookingId(null);
    });
  };

  return (
    <div style={{textAlign: "center", borderStyle: "solid"}}>
      Customer: {props.username}
      <div>
          <TextField id="outlined-basic" label="Pickup address"
            fullWidth
            onChange={ev => setPickupAddress(ev.target.value)}
            value={pickupAddress}/>
          <TextField id="outlined-basic" label="Drop off address"
            fullWidth
            onChange={ev => setDropOffAddress(ev.target.value)}
            value={dropOffAddress}/>
        <Button onClick={submit} variant="outlined" color="primary">Submit</Button>
        {bookingId && (
          <Button 
            onClick={cancel} 
            variant="outlined" 
            color="error" 
            style={{marginLeft: '10px'}}
          >
            Cancel Booking
          </Button>
        )}
      </div>
      <div style={{backgroundColor: "lightcyan", height: "50px"}}>
        {msg}
      </div>
      <div style={{backgroundColor: "lightblue", height: "50px"}}>
        {msg2}
      </div>
    </div>
  );
}

export default Customer;