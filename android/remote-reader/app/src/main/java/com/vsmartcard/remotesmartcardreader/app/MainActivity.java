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

import android.Manifest;
import android.bluetooth.BluetoothAdapter;
import android.content.DialogInterface;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ActivityInfo;
import android.content.pm.PackageManager;
import android.graphics.drawable.GradientDrawable;
import android.nfc.NfcAdapter;
import android.nfc.Tag;
import android.os.Build;
import android.os.Bundle;
import android.preference.PreferenceManager;
import android.provider.Settings;
import android.view.Menu;
import android.view.MenuItem;
import android.view.View;

import androidx.appcompat.app.AlertDialog;
import androidx.appcompat.app.AppCompatActivity;
import androidx.appcompat.widget.Toolbar;
import androidx.core.app.ActivityCompat;
import androidx.core.content.ContextCompat;

import com.example.android.common.logger.Log;
import com.example.android.common.logger.LogFragment;
import com.example.android.common.logger.LogWrapper;
import com.example.android.common.logger.MessageOnlyLogFilter;
import com.vsmartcard.remotesmartcardreader.app.screaders.*;

public class MainActivity extends AppCompatActivity implements NfcAdapter.ReaderCallback {
    private static final int REQUEST_BLUETOOTH_PERMISSIONS = 1001;

    private enum UiState {
        READY,
        WAITING_FOR_MAC,
        WAITING_FOR_CARD,
        COMMUNICATING,
        ACTION_REQUIRED,
        ERROR
    }

    private VPCDWorker vpcdTest;
    private AlertDialog dialog;
    private AlertDialog bluetoothDialog;
    private int oldOrientation = ActivityInfo.SCREEN_ORIENTATION_UNSPECIFIED;
    private androidx.appcompat.widget.AppCompatTextView statusBadgeView;
    private androidx.appcompat.widget.AppCompatTextView statusHeadlineView;
    private androidx.appcompat.widget.AppCompatTextView statusDetailView;
    private androidx.appcompat.widget.AppCompatTextView transportSummaryView;
    private androidx.appcompat.widget.AppCompatTextView lastEventView;
    private UiState uiState = UiState.READY;
    private String lastLogMessage = "";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        setContentView(R.layout.activity_main);
        Toolbar toolbar = findViewById(R.id.toolbar);
        setSupportActionBar(toolbar);
        toolbar.setTitle(R.string.app_name);
        toolbar.setSubtitle(R.string.main_toolbar_subtitle);

        statusBadgeView = findViewById(R.id.status_badge);
        statusHeadlineView = findViewById(R.id.status_headline);
        statusDetailView = findViewById(R.id.status_detail);
        transportSummaryView = findViewById(R.id.transport_summary);
        lastEventView = findViewById(R.id.last_event_value);

        findViewById(R.id.open_settings_button).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                startActivity(new Intent(MainActivity.this, SettingsActivity.class));
            }
        });
        findViewById(R.id.open_bluetooth_settings_button).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                startActivity(new Intent(Settings.ACTION_BLUETOOTH_SETTINGS));
            }
        });
        findViewById(R.id.open_nfc_settings_button).setOnClickListener(new View.OnClickListener() {
            @Override
            public void onClick(View view) {
                startActivity(new Intent(Settings.ACTION_NFC_SETTINGS));
            }
        });

        renderStatusCard();
    }

    @Override
    public boolean onCreateOptionsMenu(Menu menu) {
        // Inflate the menu; this adds items to the action bar if it is present.
        getMenuInflater().inflate(R.menu.menu_main, menu);
        return true;
    }

    @Override
    public boolean onOptionsItemSelected(MenuItem item) {
        // Handle action bar item clicks here. The action bar will
        // automatically handle clicks on the Home/Up button, so long
        // as you specify a parent activity in AndroidManifest.xml.
        int id = item.getItemId();

        if (id == R.id.action_settings) {
            startActivity(new Intent(this, SettingsActivity.class));
            return true;
        }

        return super.onOptionsItemSelected(item);
    }

    @Override
    protected  void onStart() {
        super.onStart();
        initializeLogging();
        renderStatusCard();
    }

    /** Create a chain of targets that will receive log data */
    private void initializeLogging() {
        LogWrapper logWrapper = new LogWrapper();
        Log.setLogNode(logWrapper);

        StatusLogNode statusNode = new StatusLogNode(new StatusLogNode.Listener() {
            @Override
            public void onLogLine(int priority, String tag, String msg, Throwable tr) {
                handleLogLine(msg);
            }
        });
        logWrapper.setNext(statusNode);

        MessageOnlyLogFilter msgFilter = new MessageOnlyLogFilter();
        statusNode.setNext(msgFilter);

        LogFragment logFragment = (LogFragment) getSupportFragmentManager()
                .findFragmentById(R.id.log_fragment);
        if (logFragment != null) {
            msgFilter.setNext(logFragment.getLogView());
        }
    }

    @Override
    public void onPause() {
        super.onPause();
        vpcdDisconnect();
        disableReaderMode();
        renderStatusCard();
    }

    private void enableReaderMode() {
        NfcAdapter adapter = NfcAdapter.getDefaultAdapter(this);
        if (adapter == null) {
            renderStatusCard();
            return;
        }
        if (!adapter.isEnabled()) {
            if (dialog == null) {
                dialog = new AlertDialog.Builder(this)
                        .setMessage("NFC is required to communicate with a contactless smart card. Do you want to enable NFC now?")
                        .setTitle("Enable NFC")
                        .setPositiveButton(android.R.string.yes, new DialogInterface.OnClickListener() {
                            public void onClick(DialogInterface dialog, int id) {
                                startActivity(new Intent(Settings.ACTION_NFC_SETTINGS));
                            }
                        })
                        .setNegativeButton(android.R.string.no, new DialogInterface.OnClickListener() {
                            public void onClick(DialogInterface dialog, int id) {
                            }
                        }).create();
            }
            dialog.show();
        }

        // avoid re-starting the App and loosing the tag by rotating screen
        oldOrientation = getRequestedOrientation();
        setRequestedOrientation(ActivityInfo.SCREEN_ORIENTATION_NOSENSOR);

        SharedPreferences SP = PreferenceManager.getDefaultSharedPreferences(this);
        int timeout = Integer.parseInt(SP.getString("delay", "500"));
        Bundle bundle = new Bundle();
        bundle.putInt(NfcAdapter.EXTRA_READER_PRESENCE_CHECK_DELAY, timeout * 10);
        adapter.enableReaderMode(this, this,
                NfcAdapter.FLAG_READER_NFC_A | NfcAdapter.FLAG_READER_NFC_B | NfcAdapter.FLAG_READER_SKIP_NDEF_CHECK,
                bundle);
    }

    private void disableReaderMode() {
        if (dialog != null) {
            dialog.dismiss();
        }
        if (bluetoothDialog != null) {
            bluetoothDialog.dismiss();
        }

        setRequestedOrientation(oldOrientation);

        NfcAdapter nfc = NfcAdapter.getDefaultAdapter(this);
        if (nfc != null) {
            nfc.disableReaderMode(this);
        }
    }

    @Override
    public void onTagDiscovered(Tag tag) {
        vpcdDisconnect();
        if (!ensureBluetoothTransportReady(false)) {
            Log.i(getClass().getName(), "Bluetooth transport is not ready. Fix Bluetooth settings and try again.");
            return;
        }
        String[] techList = tag.getTechList();
        for (String aTechList : techList) {
            if (aTechList.equals("android.nfc.tech.NfcA")) {
                Log.i(getClass().getName(), "Discovered ISO/IEC 14443-A tag");
            } else if (aTechList.equals("android.nfc.tech.NfcB")) {
                Log.i(getClass().getName(), "Discovered ISO/IEC 14443-B tag");
            }
        }
        NFCReader nfcReader = NFCReader.get(tag, this);
        if (nfcReader != null) {
            vpcdConnect(nfcReader);
        }
    }

    private void vpcdConnect(SCReader scReader) {
        final SharedPreferences SP = PreferenceManager.getDefaultSharedPreferences(this);
        final int port = Integer.parseInt(SP.getString("port", Integer.toString(VPCDWorker.DEFAULT_PORT)));
        final String hostname = SP.getString("hostname", VPCDWorker.DEFAULT_HOSTNAME);
        final boolean listen = SP.getBoolean("listen", VPCDWorker.DEFAULT_LISTEN);
        final TransportMode transportMode = TransportMode.fromPreference(
                SP.getString("transport_mode", TransportMode.DEFAULT_PREFERENCE_VALUE));
        final String bluetoothAddress = SP.getString("bluetooth_address", "");
        if (transportMode == TransportMode.BLUETOOTH_CLIENT && bluetoothAddress.trim().isEmpty()) {
            showBluetoothAddressDialog();
            Log.i(getClass().getName(), "Bluetooth transport selected, but the Mac Bluetooth address is empty.");
            return;
        }
        vpcdTest = new VPCDWorker();
        vpcdTest.execute(new VPCDWorker.VPCDWorkerParams(
                hostname, port, scReader, listen, transportMode, bluetoothAddress));
    }

    private void vpcdDisconnect() {
        if (vpcdTest != null) {
            vpcdTest.cancel(true);
            vpcdTest = null;
        }
        if (uiState != UiState.ERROR) {
            uiState = UiState.READY;
        }
    }

    @Override
    public void onResume() {
        super.onResume();
        /* See https://github.com/frankmorgner/vsmartcard/issues/281
        Intent intent = getIntent();
        // Check to see that the Activity started due to a discovered tag
        if (NfcAdapter.ACTION_TECH_DISCOVERED.equals(intent.getAction())) {
            vpcdDisconnect();
            NFCReader nfcReader = NFCReader.get(intent, this);
            if (nfcReader != null) {
                vpcdConnect(nfcReader);
            } else {
                super.onNewIntent(intent);
            }
        }
        */
        enableReaderMode();
        ensureBluetoothTransportReady(true);
        renderStatusCard();
    }

    @Override
    public void onNewIntent(Intent intent) {
        // onResume gets called after this to handle the intent
        super.onNewIntent(intent);
        setIntent(intent);
    }

    private boolean ensureBluetoothTransportReady(boolean interactive) {
        final SharedPreferences sp = PreferenceManager.getDefaultSharedPreferences(this);
        final TransportMode transportMode = TransportMode.fromPreference(
                sp.getString("transport_mode", TransportMode.DEFAULT_PREFERENCE_VALUE));
        if (transportMode != TransportMode.BLUETOOTH_CLIENT
                && transportMode != TransportMode.BLUETOOTH_SERVER) {
            dismissBluetoothDialog();
            return true;
        }

        final String bluetoothAddress = sp.getString("bluetooth_address", "");
        if (transportMode == TransportMode.BLUETOOTH_CLIENT && bluetoothAddress.trim().isEmpty()) {
            Log.i(getClass().getName(), "Bluetooth transport selected, but no Mac Bluetooth address is configured.");
            if (interactive) {
                showBluetoothAddressDialog();
            }
            uiState = UiState.ACTION_REQUIRED;
            renderStatusCard();
            return false;
        }

        final BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        if (adapter == null) {
            Log.i(getClass().getName(), "Bluetooth is not available on this device.");
            if (interactive) {
                showBluetoothUnavailableDialog();
            }
            uiState = UiState.ACTION_REQUIRED;
            renderStatusCard();
            return false;
        }

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
                && (!hasPermission(Manifest.permission.BLUETOOTH_CONNECT)
                || !hasPermission(Manifest.permission.BLUETOOTH_SCAN))) {
            if (interactive) {
                showBluetoothPermissionDialog();
            }
            Log.i(getClass().getName(), "Bluetooth permission is required for Bluetooth transport.");
            uiState = UiState.ACTION_REQUIRED;
            renderStatusCard();
            return false;
        }

        if (!adapter.isEnabled()) {
            if (interactive) {
                showBluetoothDisabledDialog();
            }
            Log.i(getClass().getName(), "Bluetooth is disabled.");
            uiState = UiState.ACTION_REQUIRED;
            renderStatusCard();
            return false;
        }

        dismissBluetoothDialog();
        if (uiState == UiState.ACTION_REQUIRED) {
            uiState = UiState.READY;
        }
        renderStatusCard();
        return true;
    }

    @Override
    public void onRequestPermissionsResult(int requestCode, String[] permissions, int[] grantResults) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults);
        if (requestCode == REQUEST_BLUETOOTH_PERMISSIONS) {
            boolean granted = true;
            for (int grantResult : grantResults) {
                if (grantResult != PackageManager.PERMISSION_GRANTED) {
                    granted = false;
                    break;
                }
            }
            if (grantResults.length > 0 && granted) {
                Log.i(getClass().getName(), "Bluetooth permission granted.");
                dismissBluetoothDialog();
                uiState = UiState.READY;
            } else {
                Log.i(getClass().getName(), "Bluetooth permission denied.");
                showBluetoothPermissionDialog();
                uiState = UiState.ACTION_REQUIRED;
            }
            renderStatusCard();
        }
    }

    private void showBluetoothPermissionDialog() {
        showBluetoothDialog(
                "Bluetooth permission required",
                "Bluetooth transport needs Bluetooth permissions to advertise itself or connect to a paired Mac.",
                "Grant permission",
                new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialogInterface, int i) {
                        ActivityCompat.requestPermissions(
                                MainActivity.this,
                                new String[]{
                                        Manifest.permission.BLUETOOTH_SCAN,
                                        Manifest.permission.BLUETOOTH_CONNECT
                                },
                                REQUEST_BLUETOOTH_PERMISSIONS);
                    }
                },
                "App settings",
                new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialogInterface, int i) {
                        Intent intent = new Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS);
                        intent.setData(android.net.Uri.parse("package:" + getPackageName()));
                        startActivity(intent);
                    }
                }
        );
    }

    private void showBluetoothDisabledDialog() {
        showBluetoothDialog(
                "Enable Bluetooth",
                "Bluetooth transport is selected, but Bluetooth is currently off.",
                "Open Bluetooth settings",
                new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialogInterface, int i) {
                        startActivity(new Intent(Settings.ACTION_BLUETOOTH_SETTINGS));
                    }
                },
                null,
                null
        );
    }

    private void showBluetoothAddressDialog() {
        showBluetoothDialog(
                "Mac Bluetooth address needed",
                "Legacy Bluetooth client mode needs your Mac Bluetooth address. Open Settings or a vpcd://bluetooth?address=... link.",
                "Open app settings",
                new DialogInterface.OnClickListener() {
                    @Override
                    public void onClick(DialogInterface dialogInterface, int i) {
                        startActivity(new Intent(MainActivity.this, SettingsActivity.class));
                    }
                },
                null,
                null
        );
    }

    private void showBluetoothUnavailableDialog() {
        showBluetoothDialog(
                "Bluetooth unavailable",
                "This device does not expose Bluetooth Classic, so Bluetooth transport cannot be used here.",
                android.R.string.ok,
                null,
                null,
                null
        );
    }

    private void showBluetoothDialog(String title,
                                     String message,
                                     String positiveText,
                                     DialogInterface.OnClickListener positiveAction,
                                     String neutralText,
                                     DialogInterface.OnClickListener neutralAction) {
        dismissBluetoothDialog();
        AlertDialog.Builder builder = new AlertDialog.Builder(this)
                .setTitle(title)
                .setMessage(message)
                .setCancelable(true)
                .setNegativeButton(android.R.string.cancel, null);

        if (positiveText != null) {
            builder.setPositiveButton(positiveText, positiveAction);
        } else {
            builder.setPositiveButton(android.R.string.ok, positiveAction);
        }
        if (neutralText != null) {
            builder.setNeutralButton(neutralText, neutralAction);
        }
        bluetoothDialog = builder.create();
        bluetoothDialog.show();
    }

    private void showBluetoothDialog(String title,
                                     String message,
                                     int positiveTextRes,
                                     DialogInterface.OnClickListener positiveAction,
                                     String neutralText,
                                     DialogInterface.OnClickListener neutralAction) {
        showBluetoothDialog(title, message, getString(positiveTextRes), positiveAction, neutralText, neutralAction);
    }

    private void dismissBluetoothDialog() {
        if (bluetoothDialog != null && bluetoothDialog.isShowing()) {
            bluetoothDialog.dismiss();
        }
        bluetoothDialog = null;
    }

    private boolean hasPermission(String permission) {
        return ContextCompat.checkSelfPermission(this, permission) == PackageManager.PERMISSION_GRANTED;
    }

    private void handleLogLine(final String msg) {
        if (msg == null || msg.trim().isEmpty()) {
            return;
        }
        runOnUiThread(new Runnable() {
            @Override
            public void run() {
                lastLogMessage = msg.trim();
                if (msg.startsWith("ERROR:")) {
                    uiState = UiState.ERROR;
                } else if (msg.startsWith("Listening on") || msg.startsWith("Waiting for connections")) {
                    uiState = UiState.WAITING_FOR_MAC;
                } else if (msg.startsWith("Connected,")) {
                    uiState = UiState.WAITING_FOR_CARD;
                } else if (msg.startsWith("Discovered ISO/IEC")
                        || msg.startsWith("Powered up the card")
                        || msg.startsWith("Reset the card")
                        || msg.startsWith("C-APDU:")
                        || msg.startsWith("R-APDU:")) {
                    uiState = UiState.COMMUNICATING;
                } else if (msg.contains("permission is required")
                        || msg.contains("Bluetooth is disabled")
                        || msg.contains("not available")
                        || msg.contains("transport is not ready")
                        || msg.contains("Bluetooth transport selected, but no Mac Bluetooth address is configured.")) {
                    uiState = UiState.ACTION_REQUIRED;
                } else if (msg.startsWith("Disconnected from VPCD")
                        || msg.startsWith("Closing listening transport")
                        || msg.startsWith("End of stream")) {
                    uiState = UiState.READY;
                }
                renderStatusCard();
            }
        });
    }

    private void renderStatusCard() {
        if (statusBadgeView == null) {
            return;
        }

        TransportMode transportMode = currentTransportMode();
        transportSummaryView.setText(buildTransportSummary(transportMode));
        if (lastLogMessage.isEmpty()) {
            lastEventView.setText(R.string.status_last_event_idle);
        } else {
            lastEventView.setText(lastLogMessage);
        }

        if (!isNfcAvailable()) {
            applyPresentation(
                    R.string.status_badge_action,
                    R.color.colorStatusError,
                    R.string.status_headline_action_required,
                    R.string.status_detail_nfc_unavailable);
            return;
        }

        if (!isNfcEnabled()) {
            applyPresentation(
                    R.string.status_badge_action,
                    R.color.colorStatusWaiting,
                    R.string.status_headline_action_required,
                    R.string.status_detail_nfc_off);
            return;
        }

        BlockingBluetoothIssue bluetoothIssue = getBlockingBluetoothIssue(transportMode);
        if (bluetoothIssue != null) {
            applyPresentation(
                    R.string.status_badge_action,
                    bluetoothIssue.badgeColorRes,
                    R.string.status_headline_action_required,
                    bluetoothIssue.detailRes);
            return;
        }

        switch (uiState) {
            case ERROR:
                applyPresentation(
                        R.string.status_badge_error,
                        R.color.colorStatusError,
                        R.string.status_headline_error,
                        getString(R.string.status_detail_error_prefix) + "\n" + lastLogMessage);
                break;
            case WAITING_FOR_MAC:
                applyPresentation(
                        R.string.status_badge_waiting,
                        R.color.colorStatusWaiting,
                        R.string.status_headline_waiting_for_mac,
                        R.string.status_detail_waiting_for_mac);
                break;
            case WAITING_FOR_CARD:
                applyPresentation(
                        R.string.status_badge_live,
                        R.color.colorStatusReady,
                        R.string.status_headline_waiting_for_card,
                        R.string.status_detail_waiting_for_card);
                break;
            case COMMUNICATING:
                applyPresentation(
                        R.string.status_badge_live,
                        R.color.colorStatusWorking,
                        R.string.status_headline_communicating,
                        R.string.status_detail_communicating);
                break;
            case ACTION_REQUIRED:
                applyPresentation(
                        R.string.status_badge_action,
                        R.color.colorStatusWaiting,
                        R.string.status_headline_action_required,
                        R.string.status_detail_bluetooth_permission);
                break;
            case READY:
            default:
                applyDefaultReadyPresentation(transportMode);
                break;
        }
    }

    private void applyDefaultReadyPresentation(TransportMode transportMode) {
        if (transportMode == TransportMode.TCP) {
            applyPresentation(
                    R.string.status_badge_ready,
                    R.color.colorStatusReady,
                    R.string.status_headline_ready_tcp,
                    R.string.status_detail_ready_tcp);
            return;
        }
        applyPresentation(
                R.string.status_badge_ready,
                R.color.colorStatusReady,
                R.string.status_headline_ready_bluetooth_server,
                R.string.status_detail_ready_bluetooth_server);
    }

    private void applyPresentation(int badgeTextRes, int badgeColorRes, int headlineRes, int detailRes) {
        applyPresentation(badgeTextRes, badgeColorRes, getString(headlineRes), getString(detailRes));
    }

    private void applyPresentation(int badgeTextRes, int badgeColorRes, int headlineRes, String detail) {
        applyPresentation(badgeTextRes, badgeColorRes, getString(headlineRes), detail);
    }

    private void applyPresentation(int badgeTextRes, int badgeColorRes, String headline, String detail) {
        statusBadgeView.setText(badgeTextRes);
        statusHeadlineView.setText(headline);
        statusDetailView.setText(detail);

        GradientDrawable badgeBackground = new GradientDrawable();
        badgeBackground.setShape(GradientDrawable.RECTANGLE);
        badgeBackground.setCornerRadius(getResources().getDisplayMetrics().density * 999f);
        badgeBackground.setColor(ContextCompat.getColor(this, badgeColorRes));
        statusBadgeView.setBackground(badgeBackground);
    }

    private TransportMode currentTransportMode() {
        SharedPreferences sp = PreferenceManager.getDefaultSharedPreferences(this);
        return TransportMode.fromPreference(
                sp.getString("transport_mode", TransportMode.DEFAULT_PREFERENCE_VALUE));
    }

    private String buildTransportSummary(TransportMode transportMode) {
        SharedPreferences sp = PreferenceManager.getDefaultSharedPreferences(this);
        if (transportMode == TransportMode.TCP) {
            String hostname = sp.getString("hostname", VPCDWorker.DEFAULT_HOSTNAME);
            int port = Integer.parseInt(sp.getString("port", Integer.toString(VPCDWorker.DEFAULT_PORT)));
            return getString(R.string.transport_summary_tcp, hostname, port);
        }
        if (transportMode == TransportMode.BLUETOOTH_CLIENT) {
            String address = sp.getString("bluetooth_address", "");
            if (address.trim().isEmpty()) {
                address = getString(R.string.transport_summary_not_configured);
            }
            return getString(R.string.transport_summary_bluetooth_client, address);
        }
        return getString(R.string.transport_summary_bluetooth_server);
    }

    private boolean isNfcAvailable() {
        return NfcAdapter.getDefaultAdapter(this) != null;
    }

    private boolean isNfcEnabled() {
        NfcAdapter adapter = NfcAdapter.getDefaultAdapter(this);
        return adapter != null && adapter.isEnabled();
    }

    private BlockingBluetoothIssue getBlockingBluetoothIssue(TransportMode transportMode) {
        if (transportMode != TransportMode.BLUETOOTH_CLIENT && transportMode != TransportMode.BLUETOOTH_SERVER) {
            return null;
        }

        BluetoothAdapter adapter = BluetoothAdapter.getDefaultAdapter();
        if (adapter == null) {
            return new BlockingBluetoothIssue(R.string.status_detail_bluetooth_unavailable, R.color.colorStatusError);
        }
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S
                && (!hasPermission(Manifest.permission.BLUETOOTH_CONNECT)
                || !hasPermission(Manifest.permission.BLUETOOTH_SCAN))) {
            return new BlockingBluetoothIssue(R.string.status_detail_bluetooth_permission, R.color.colorStatusWaiting);
        }
        if (!adapter.isEnabled()) {
            return new BlockingBluetoothIssue(R.string.status_detail_bluetooth_off, R.color.colorStatusWaiting);
        }

        if (transportMode == TransportMode.BLUETOOTH_CLIENT) {
            SharedPreferences sp = PreferenceManager.getDefaultSharedPreferences(this);
            String address = sp.getString("bluetooth_address", "");
            if (address.trim().isEmpty()) {
                return new BlockingBluetoothIssue(R.string.status_detail_bluetooth_address_missing, R.color.colorStatusWaiting);
            }
        }
        return null;
    }

    private static class BlockingBluetoothIssue {
        final int detailRes;
        final int badgeColorRes;

        BlockingBluetoothIssue(int detailRes, int badgeColorRes) {
            this.detailRes = detailRes;
            this.badgeColorRes = badgeColorRes;
        }
    }

}
