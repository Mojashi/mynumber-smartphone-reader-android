package com.vsmartcard.remotesmartcardreader.app;

import android.bluetooth.BluetoothAdapter;
import android.bluetooth.BluetoothDevice;
import android.bluetooth.BluetoothSocket;

import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.util.UUID;

class BluetoothClientTransport implements VPCDTransport {
    static final String DEFAULT_SERVICE_UUID = "00001101-0000-1000-8000-00805f9b34fb";

    private final String deviceAddress;
    private final UUID serviceUuid;

    BluetoothClientTransport(String deviceAddress, String serviceUuid) {
        this.deviceAddress = deviceAddress;
        this.serviceUuid = UUID.fromString(serviceUuid);
    }

    @Override
    public VPCDConnection open() throws IOException {
        final BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        if (adapter == null) {
            throw new IOException("Bluetooth is not available on this device.");
        }
        if (!adapter.isEnabled()) {
            throw new IOException("Bluetooth is disabled.");
        }
        if (deviceAddress == null || deviceAddress.trim().isEmpty()) {
            throw new IOException("Bluetooth device address is empty.");
        }

        adapter.cancelDiscovery();
        final BluetoothDevice device;
        try {
            device = adapter.getRemoteDevice(deviceAddress.trim());
        } catch (IllegalArgumentException e) {
            throw new IOException("Invalid Bluetooth device address: " + deviceAddress, e);
        }

        final BluetoothSocket socket = device.createRfcommSocketToServiceRecord(serviceUuid);
        socket.connect();
        return new BluetoothSocketConnection(socket);
    }

    @Override
    public boolean isReusable() {
        return false;
    }

    @Override
    public String describeEndpoint() {
        return deviceAddress;
    }

    @Override
    public void close() {
    }
}
