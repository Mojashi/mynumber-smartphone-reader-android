package com.vsmartcard.remotesmartcardreader.app;

import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothSocket;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;

class BluetoothSocketConnection implements VPCDConnection {
    private final BluetoothSocket socket;
    private final BluetoothDevice device;

    BluetoothSocketConnection(BluetoothSocket socket) {
        this.socket = socket;
        this.device = socket.getRemoteDevice();
    }

    @Override
    public InputStream getInputStream() throws IOException {
        return socket.getInputStream();
    }

    @Override
    public OutputStream getOutputStream() throws IOException {
        return socket.getOutputStream();
    }

    @Override
    public String describePeer() {
        if (device == null) {
            return "Bluetooth peer";
        }
        final String name = device.getName();
        if (name != null && !name.isEmpty()) {
            return name + " (" + device.getAddress() + ")";
        }
        return device.getAddress();
    }

    @Override
    public void close() throws IOException {
        socket.close();
    }
}
