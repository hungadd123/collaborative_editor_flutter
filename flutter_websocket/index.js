const WebSocket = require('ws');

const wss = new WebSocket.Server({ port: 8081 , host: '0.0.0.0'});

wss.on('connection', function connection(ws) {
  console.log('Client connected');

  ws.on('message', function incoming(message) {
    console.log('Received:', message);

    let data;
    try {
      data = JSON.parse(message);
    } catch (e) {
      console.error("Invalid JSON received");
      return;
    }
    // console.log(`[WS] Received update from ${parsed.user_id}`);
    // console.log(`[WS] Broadcasting to ${clients.size - 1} clients`);

    // Broadcast version_update hoặc delta_update
    if (data.type === 'version_update') {
      // Chỉ broadcast version_update
      wss.clients.forEach(function each(client) {
        if (client !== ws && client.readyState === WebSocket.OPEN) {
          client.send(JSON.stringify({
            type: 'version_update',
            document_id: data.document_id,
            version_number: data.version_number,
            user_id: data.user_id,
          }));
        }
      });
    } 
    
    if(data.type === 'delta_update'){
      // Broadcast các message khác (ví dụ delta_update)
      wss.clients.forEach(function each(client) {
        if (client !== ws && client.readyState === WebSocket.OPEN) {
          client.send(message);
        }
      });
    }
  });

  ws.on('close', () => {
    console.log('Client disconnected');
  });
});

console.log('✅ WebSocket server is running on ws://localhost:8081');
