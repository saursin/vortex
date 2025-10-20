#include "debug_server.h"
#include <arpa/inet.h>
#include <cstring>
#include <iostream>
#include <netinet/in.h>
#include <sstream>
#include <iomanip>
#include <sys/socket.h>
#include <unistd.h>

DebugServer::DebugServer() = default;

DebugServer::~DebugServer() {
  stop();
}

void DebugServer::start(int port, Callbacks cb) {
  if (running_.exchange(true))
    return; // already running
  cb_ = std::move(cb);
  server_thread_ = std::thread(&DebugServer::server_loop, this, port);
  server_thread_.detach();
}

void DebugServer::stop() {
  running_.store(false);
  if (server_fd_ >= 0) {
    close(server_fd_); // Wake up accept() call
  }
  if (server_thread_.joinable()) {
    server_thread_.join(); // Wait for clean shutdown
  }
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
  server_fd_ = socket(AF_INET, SOCK_STREAM, 0);
  if (server_fd_ < 0) {
    perror("[VXDBG] socket");
    return;
  }

  int opt = 1;
  setsockopt(server_fd_, SOL_SOCKET, SO_REUSEADDR, &opt, sizeof(opt));

  sockaddr_in addr{};
  addr.sin_family = AF_INET;
  addr.sin_addr.s_addr = INADDR_ANY;
  addr.sin_port = htons(port);

  if (bind(server_fd_, (sockaddr*)&addr, sizeof(addr)) < 0) {
    perror("[VXDBG] bind");
    close(server_fd_);
    return;
  }

  listen(server_fd_, 1);
  
  // Accept multiple sequential connections
  while (running_.load()) {
    sockaddr_in client{};
    socklen_t len = sizeof(client);
    client_fd_ = accept(server_fd_, (sockaddr*)&client, &len);
    if (client_fd_ < 0) {
      if (running_.load()) {  // Only print error if we're supposed to be running
        perror("[VXDBG] accept");
      }
      break;
    }

    connected_.store(true);
    std::cout << "[VXDBG] Debugger connected.\n";

    // Handle this client connection
    recv_buffer_.clear();  // Clear buffer for new connection
    while (running_.load()) {
      char tmp[128];
      ssize_t n = read(client_fd_, tmp, sizeof(tmp));
      if (n <= 0) break; // connection closed or error
      recv_buffer_.append(tmp, n);

      // check if we have a full command (newline-terminated)
      size_t pos;
      while ((pos = recv_buffer_.find('\n')) != std::string::npos) {
        std::string cmd = recv_buffer_.substr(0, pos);
        recv_buffer_.erase(0, pos + 1);
        if (!cmd.empty()) {
          execute_command(cmd);
        }
      }
    }

    connected_.store(false);
    close(client_fd_);
    std::cout << "[VXDBG] Debugger disconnected.\n";
  }
  
  close(server_fd_);
}


void DebugServer::execute_command(const std::string &cmd) {
  std::cout << "[VXDBG] RX: " << cmd << std::endl;  // Debug output
  
  // helper to write response
  auto write_resp = [&](bool ack, const std::string& payload = "") {
    int rc = 0;
    if (!ack) {
      std::cout << "[VXDBG] TX: -" << std::endl;  // Debug output
      rc = ::write(client_fd_, "-\n", 2);
    } else {
      std::string msg = "+" + payload + "\n";
      std::cout << "[VXDBG] TX: " << msg.substr(0, msg.length()-1) << std::endl;  // Debug output
      rc = ::write(client_fd_, msg.c_str(), msg.size());
    }

    if (rc < 0) {
      perror("[VXDBG] write");
      running_.store(false);
    }
  };

  char sbuf[1024];
  // -------------------------------------------------------------------------
  if (cmd[0] == 'r') {               // Read Single DM Register
    // Format: r<addr>
    // Resp: "+<value>\n" or "-\n"
    uint32_t addr;
    try {
      addr = std::stoul(cmd.substr(1), nullptr, 16);
    }
    catch (...) {
      write_resp(false);
      return;
    }

    uint32_t val = 0;     
    bool ok = cb_.on_read_reg && cb_.on_read_reg(addr, &val) == 0;

    if (!ok) {
      write_resp(false);
      return;
    }
    snprintf(sbuf, sizeof(sbuf), "%08x", val);
    write_resp(true, sbuf);
  }
  // -------------------------------------------------------------------------
  else if (cmd[0] == 'R') {      // Read Multiple DM Registers -> sequential
    // Format: R<addr>,<length>
    // Resp: "+<value1>,<value2>,...\n" or "-\n"
    std::vector<uint32_t> addrs;
    
    // parse addresses
    std::stringstream ss(cmd.substr(1)); // Remove 'R' prefix once
    std::string tok;
    while (std::getline(ss, tok, ',')) {
      try {
        addrs.push_back(std::stoul(tok, nullptr, 16)); // No substr here
      }
      catch (...) {
        write_resp(false);
        return;
      }
    }

    if (addrs.empty()) {
      write_resp(false);
      return;
    }

    std::ostringstream oss;
    bool ok = true;
    for (size_t i = 0; i < addrs.size(); ++i) {
      uint32_t v = 0;
      if (!cb_.on_read_reg || cb_.on_read_reg(addrs[i], &v) != 0) {
          ok = false;
          break;
      }
      oss << std::hex << std::setw(8) << std::setfill('0') << v;
      if (i + 1 < addrs.size()) oss << ",";
    }
    if (!ok) {
      write_resp(false);
      return;
    }
    write_resp(true, oss.str());
  }
  // -------------------------------------------------------------
  else if (cmd[0] == 'w') {  // single write
    size_t comma_pos = cmd.find(',');
    if (comma_pos == std::string::npos) {
      write_resp(false);  // parse error
      return;
    }

    uint32_t addr, val;
    try {
      addr = std::stoul(cmd.substr(1, comma_pos - 1), nullptr, 16);
      val  = std::stoul(cmd.substr(comma_pos + 1), nullptr, 16);
    } catch (...) {
      write_resp(false);  // parse error
      return;
    }

    bool ok = cb_.on_write_reg && cb_.on_write_reg(addr, val) == 0;
    write_resp(ok);
  }
  // -------------------------------------------------------------
  else if (cmd[0] == 'W') {  // multi write non-sequential: Waddr1,addr2;val1,val2
    size_t colon_pos = cmd.find(':');
    if (colon_pos == std::string::npos) {
      write_resp(false);
      return;
    }

    std::vector<uint32_t> addrs, vals;
    // Parse addresses
    {
      std::stringstream ss(cmd.substr(1, colon_pos - 1));
      std::string tok;
      while (std::getline(ss, tok, ',')) {
        try {
          addrs.push_back(std::stoul(tok, nullptr, 16));
        } catch (...) {
          write_resp(false);
          return;
        }
      }
    }
    // Parse values
    {
      std::stringstream ss(cmd.substr(colon_pos + 1));
      std::string tok;
      while (std::getline(ss, tok, ',')) {
        try {
          vals.push_back(std::stoul(tok, nullptr, 16));
        } catch (...) {
          write_resp(false);
          return;
        }
      }
    }

    if(vals.size() != addrs.size()) {
      write_resp(false);
      return;
    }

    bool ok = true;
    for (size_t i = 0; i < addrs.size(); ++i) {
      ok = cb_.on_write_reg && cb_.on_write_reg(addrs[i], vals[i]) == 0;
      if (!ok) 
        break;
    }   
    write_resp(ok);
  }
  // -------------------------------------------------------------
  else if (cmd[0] == 'p') {
    write_resp(true, "P");
  }
  else if (cmd[0] == 'q') {
    write_resp(true);
    running_.store(false);
  }
  else {
    write_resp(false);
  }
}