/*
 * Copyright (C) 2014 Frank Morgner
 *
 * This file is part of RemoteSmartCardReader.
 *
 * RemoteSmartCardReader is free software: you can redistribute it and/or
 * modify it under the terms of the GNU General Public License as published by
 * the Free Software Foundation, either version 3 of the License, or (at your
 * option) any later version.
 *
 * RemoteSmartCardReader is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of MERCHANTABILITY
 * or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General Public License for
 * more details.
 *
 * You should have received a copy of the GNU General Public License along with
 * RemoteSmartCardReader.  If not, see <http://www.gnu.org/licenses/>.
 */

package com.vsmartcard.remotesmartcardreader.app;

import android.os.AsyncTask;

import androidx.annotation.Nullable;

import com.example.android.common.logger.Log;
import com.vsmartcard.remotesmartcardreader.app.screaders.SCReader;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

class VPCDWorker extends AsyncTask<VPCDWorker.VPCDWorkerParams, Void, Void> {

    public static class VPCDWorkerParams {
        final String hostname;
        final int port;
        final SCReader reader;
        final boolean listen;
        final TransportMode transportMode;
        final String bluetoothAddress;

        VPCDWorkerParams(String hostname, int port, SCReader reader, boolean listen,
                         TransportMode transportMode, String bluetoothAddress) {
            this.hostname = hostname;
            this.port = port;
            this.reader = reader;
            this.listen = listen;
            this.transportMode = transportMode;
            this.bluetoothAddress = bluetoothAddress;
        }
    }

    public static final int DEFAULT_PORT = 35963;
    // default URI when used in emulator
    public static final String DEFAULT_HOSTNAME = "10.0.2.2";
    public static final boolean DEFAULT_LISTEN = false;

    private SCReader reader;
    private VPCDTransport transport;
    private VPCDConnection connection;
    private InputStream inputStream;
    private OutputStream outputStream;

    @Override
    protected void onCancelled () {
        try {
            closeConnection();
            if (transport != null) {
                transport.close();
            }
        } catch (IOException e) {
            e.printStackTrace();
        }
    }

    private static final int VPCD_CTRL_LEN = 1;
    private static final byte VPCD_CTRL_OFF = 0;
    private static final byte VPCD_CTRL_ON = 1;
    private static final byte VPCD_CTRL_RESET = 2;
    private static final byte VPCD_CTRL_ATR = 4;

    @Override
    public Void doInBackground(VPCDWorkerParams... params) {
        final VPCDWorkerParams workerParams = params[0];
        try {
            reader = workerParams.reader;
            transport = createTransport(workerParams);
            if (transport.isReusable()) {
                Log.i(this.getClass().getName(), "Listening on " + transport.describeEndpoint());
            } else {
                Log.i(this.getClass().getName(), "Connecting via " + workerParams.transportMode.preferenceValue()
                        + " to " + transport.describeEndpoint() + "...");
            }

            while (!isCancelled()) {
                ensureConnection();
                byte[] out = null;
                byte[] in = receiveFromVPCD();
                if (in == null) {
                    if (!transport.isReusable()) {
                        Log.i(this.getClass().getName(), "End of stream, finishing");
                        break;
                    } else {
                        Log.i(this.getClass().getName(), "End of stream, closing connection");
                        closeConnection();
                        continue; // back to accept
                    }
                }

                if (in.length == VPCD_CTRL_LEN) {
                    switch (in[0]) {
                        case VPCD_CTRL_OFF:
                            reader.powerOff();
                            Log.i(this.getClass().getName(), "Powered down the card (cold reset)");
                            break;
                        case VPCD_CTRL_ON:
                            reader.powerOn();
                            Log.i(this.getClass().getName(), "Powered up the card with ATR " + Hex.getHexString(reader.getATR()));
                            break;
                        case VPCD_CTRL_RESET:
                            reader.reset();
                            Log.i(this.getClass().getName(), "Reset the card (warm reset)");
                            break;
                        case VPCD_CTRL_ATR:
                            out = reader.getATR();
                            break;
                        default:
                            throw new IOException("Unhandled command from VPCD.");
                    }
                } else {
                    Log.i(this.getClass().getName(), "C-APDU: " + Hex.getHexString(in));
                    out = reader.transmit(in);
                    Log.i(this.getClass().getName(), "R-APDU: " + Hex.getHexString(out));
                }
                if (out != null) {
                    sendToVPCD(out);
                }
            }
        } catch (Exception e) {
            if (!isCancelled()) {
                e.printStackTrace();
                Log.i(this.getClass().getName(), "ERROR: " + e.getMessage());
            }
        }
        try {
            vpcdDisconnect();
        } catch (Exception e) {
            e.printStackTrace();
        }
        return null;
    }

    @Nullable
    private byte[] receiveFromVPCD() throws IOException {
        /* convert length from network byte order.
        Note that Java always uses network byte order internally. */
        int length1 = inputStream.read();
        int length2 = inputStream.read();
        if (length1 == -1 || length2 == -1) {
            // EOF
            return null;
        }
        int length = (length1 << 8) + length2;

        byte[] data = new byte[length];

        int offset = 0;
        while (length > 0) {
            int read = inputStream.read(data, offset, length);
            if (read == -1) {
                // EOF
                return null;
            }
            offset += read;
            length -= read;
        }

        return data;
    }

    private void sendToVPCD(byte[] data) throws IOException {
        /* convert length to network byte order.
        Note that Java always uses network byte order internally. */
        byte[] packet = new byte[2 + data.length];
        packet[0] = (byte) (data.length >> 8);
        packet[1] = (byte) (data.length & 0xff);
        System.arraycopy(data, 0, packet, 2, data.length);

        outputStream.write(packet);
        outputStream.flush();
    }

    private VPCDTransport createTransport(VPCDWorkerParams params) {
        if (params.transportMode == TransportMode.BLUETOOTH_CLIENT) {
            return new BluetoothClientTransport(params.bluetoothAddress, BluetoothClientTransport.DEFAULT_SERVICE_UUID);
        }
        if (params.transportMode == TransportMode.BLUETOOTH_SERVER) {
            return new BluetoothServerTransport(
                    BluetoothServerTransport.DEFAULT_SERVICE_NAME,
                    BluetoothServerTransport.DEFAULT_SERVICE_UUID);
        }
        if (params.listen) {
            return new TcpServerTransport(params.port);
        }
        return new TcpClientTransport(params.hostname, params.port);
    }

    private void ensureConnection() throws IOException {
        if (connection != null) {
            return;
        }

        if (transport.isReusable()) {
            Log.i(this.getClass().getName(), "Waiting for connections...");
        }
        connection = transport.open();
        inputStream = connection.getInputStream();
        outputStream = connection.getOutputStream();
        Log.i(this.getClass().getName(), "Connected, " + connection.describePeer());
    }

    private void closeConnection() {
        try {
            if (outputStream != null) {
                outputStream.close();
            }
        } catch (IOException ignored) { }
        try {
            if (inputStream != null) {
                inputStream.close();
            }
        } catch (IOException ignored) { }
        try {
            if (connection != null) {
                connection.close();
            }
        } catch (IOException ignored) { }
        outputStream = null;
        inputStream = null;
        connection = null;
    }

    private void vpcdDisconnect() throws IOException {
        if (reader != null) {
            reader.eject();
        }
        closeConnection();
        if (transport != null) {
            if (transport.isReusable()) {
                Log.i(this.getClass().getName(), "Closing listening transport");
            } else {
                Log.i(this.getClass().getName(), "Disconnected from VPCD");
            }
            transport.close();
            transport = null;
        }
    }
}
