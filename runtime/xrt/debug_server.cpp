#include "debug_server.h"
#include <arpa/inet.h>
#include <cstring>
#include <iostream>
#include <netinet/in.h>
#include <sstream>
#include <sys/socket.h>
#include <unistd.h>

DebugServer::DebugServer() = default;

DebugServer::~DebugServer() {
  running_.store(false);
  if (server_thread_.joinable())
    server_thread_.detach();
}

void DebugServer::start(int port, Callbacks cb) {
  if (running_.exchange(true))
    return; // already running
  cb_ = std::move(cb);
  server_thread_ = std::thread(&DebugServer::server_loop, this, port);
  server_thread_.detach();
}

bool DebugServer::wait_for_client(int timeout_ms) {
  int waited = 0;
  while (!connected_.load()) {
    std::this_thread::sleep_for(std::chrono::milliseconds(100));
    if (timeout_ms > 0 && (waited += 100) >= timeout_ms)
      return false;
  }
  return true;
}

void DebugServer::server_loop(int port) {
  int server_fd = socket(AF_INET, SOCK_STREAM, 0);
  if (server_fd < 0) {
    perror("[VXDBG] socket");
    return;
  }

  int opt = 1;
  setsockopt(server_fd, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = INADDR_ANY;
  addr.sin_port = htons(port);

  if (bind(server_fd, (sockaddr*)&addr, sizeof(addr)) < 0) {
    perror("[VXDBG] bind");
    close(server_fd);
    return;
  }

  listen(server_fd, 1);

  sockaddr_in client{};
  socklen_t len = sizeof(client);
  int client_fd = accept(server_fd, (sockaddr*)&client, &len);
  if (client_fd < 0) {
    perror("[VXDBG] accept");
    close(server_fd);
    return;
  }

  connected_.store(true);
  std::cout << "[VXDBG] Debugger connected.\n";

  char buffer[256];
  while (running_.load()) {
    memset(buffer, 0, sizeof(buffer));
    ssize_t n = read(client_fd, buffer, sizeof(buffer) - 1);
    if (n <= 0)
      break;

    std::istringstream iss(buffer);
    std::string cmd;
    iss >> cmd;

    if (cmd == "r") {
      uint32_t addr;
      iss >> std::hex >> addr;
      uint32_t val = 0;
      if (cb_.on_read_reg)
        cb_.on_read_reg(addr, &val);
      std::ostringstream resp;
      resp << "ACK " << std::hex << val << "\n";
      (void)write(client_fd, resp.str().c_str(), resp.str().size());

    } else if (cmd == "w") {
      uint32_t addr, val;
      iss >> std::hex >> addr >> val;
      if (cb_.on_write_reg)
        cb_.on_write_reg(addr, val);
      (void)write(client_fd, "ACK\n", 4);

    } 
    else if (cmd == "ping") {
      (void)write(client_fd, "ACK pong\n", 9);
    }
    else if (cmd == "quit") {
      (void)write(client_fd, "ACK\n", 4);
      break;
    } else {
      (void)write(client_fd, "ERR\n", 4);
    }
  }

  connected_.store(false);
  close(client_fd);
  close(server_fd);
  std::cout << "[VXDBG] Debugger disconnected.\n";
}
