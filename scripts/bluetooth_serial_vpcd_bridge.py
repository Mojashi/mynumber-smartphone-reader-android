#!/usr/bin/env python3

import argparse
import fcntl
import os
import selectors
import socket
import sys
import termios
import time
import tty


def log(message):
    timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
    print(f"[{timestamp}] {message}", flush=True)


def configure_raw(fd):
    attrs = termios.tcgetattr(fd)
    tty.setraw(fd)
    attrs = termios.tcgetattr(fd)
    attrs[4] = termios.B115200
    attrs[5] = termios.B115200
    termios.tcsetattr(fd, termios.TCSANOW, attrs)


def open_serial(path):
    log(f"Waiting for Bluetooth serial connection on {path}")
    fd = os.open(path, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
    flags = fcntl.fcntl(fd, fcntl.F_GETFL)
    fcntl.fcntl(fd, fcntl.F_SETFL, flags & ~os.O_NONBLOCK)
    configure_raw(fd)
    log(f"Opened {path}")
    return fd


def connect_tcp(host, port, interval):
    while True:
        try:
            sock = socket.create_connection((host, port), timeout=1.0)
            sock.setblocking(False)
            log(f"Connected to VPCD on {host}:{port}")
            return sock
        except OSError as exc:
            log(f"VPCD listener not ready on {host}:{port}: {exc}")
            time.sleep(interval)


def bridge(serial_fd, tcp_sock):
    selector = selectors.DefaultSelector()
    selector.register(serial_fd, selectors.EVENT_READ, "serial")
    selector.register(tcp_sock, selectors.EVENT_READ, "tcp")

    try:
        while True:
            for key, _ in selector.select():
                if key.data == "serial":
                    data = os.read(serial_fd, 4096)
                    if not data:
                        log("Bluetooth serial side closed")
                        return
                    tcp_sock.sendall(data)
                else:
                    data = tcp_sock.recv(4096)
                    if not data:
                        log("VPCD side closed")
                        return
                    os.write(serial_fd, data)
    finally:
        selector.close()


def main():
    parser = argparse.ArgumentParser(description="Bridge macOS Bluetooth-Incoming-Port to a local VPCD TCP listener.")
    parser.add_argument("--serial", default="/dev/cu.Bluetooth-Incoming-Port")
    parser.add_argument("--tcp-host", default="127.0.0.1")
    parser.add_argument("--tcp-port", type=int, default=35963)
    parser.add_argument("--retry-interval", type=float, default=1.0)
    args = parser.parse_args()

    log(f"Bridge target is {args.tcp_host}:{args.tcp_port}")
    while True:
        serial_fd = None
        tcp_sock = None
        try:
            serial_fd = open_serial(args.serial)
            tcp_sock = connect_tcp(args.tcp_host, args.tcp_port, args.retry_interval)
            bridge(serial_fd, tcp_sock)
        except KeyboardInterrupt:
            log("Stopping bridge")
            return 0
        except Exception as exc:
            log(f"Bridge error: {exc}")
            time.sleep(args.retry_interval)
        finally:
            if tcp_sock is not None:
                try:
                    tcp_sock.close()
                except OSError:
                    pass
            if serial_fd is not None:
                try:
                    os.close(serial_fd)
                except OSError:
                    pass
            time.sleep(0.2)


if __name__ == "__main__":
    sys.exit(main())
