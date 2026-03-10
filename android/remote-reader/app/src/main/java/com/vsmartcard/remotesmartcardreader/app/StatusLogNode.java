package com.vsmartcard.remotesmartcardreader.app;

import com.example.android.common.logger.LogNode;

class StatusLogNode implements LogNode {
    interface Listener {
        void onLogLine(int priority, String tag, String msg, Throwable tr);
    }

    private final Listener listener;
    private LogNode next;

    StatusLogNode(Listener listener) {
        this.listener = listener;
    }

    @Override
    public void println(int priority, String tag, String msg, Throwable tr) {
        if (listener != null) {
            listener.onLogLine(priority, tag, msg, tr);
        }
        if (next != null) {
            next.println(priority, tag, msg, tr);
        }
    }

    public void setNext(LogNode node) {
        next = node;
    }
}
