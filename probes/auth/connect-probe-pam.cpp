#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <iostream>
#include <security/pam_appl.h>
#include <string>
#include <termios.h>
#include <unistd.h>

namespace {

struct ConversationState {
  FILE* terminal = nullptr;
};

std::string read_line(FILE* terminal, const char* prompt, bool echo) {
  std::fputs(prompt, terminal);
  std::fflush(terminal);
  const int descriptor = fileno(terminal);
  termios previous{};
  bool changed = false;
  if (!echo && tcgetattr(descriptor, &previous) == 0) {
    termios hidden = previous;
    hidden.c_lflag &= static_cast<tcflag_t>(~ECHO);
    changed = tcsetattr(descriptor, TCSAFLUSH, &hidden) == 0;
  }

  char* buffer = nullptr;
  std::size_t capacity = 0;
  const ssize_t length = getline(&buffer, &capacity, terminal);
  if (changed) {
    tcsetattr(descriptor, TCSAFLUSH, &previous);
    std::fputc('\n', terminal);
  }
  std::string value;
  if (length > 0) {
    value.assign(buffer, static_cast<std::size_t>(length));
    while (!value.empty() &&
           (value.back() == '\n' || value.back() == '\r')) {
      value.pop_back();
    }
  }
  if (buffer != nullptr) {
    explicit_bzero(buffer, capacity);
    std::free(buffer);
  }
  return value;
}

int converse(int message_count, const pam_message** messages,
             pam_response** responses, void* application_data) {
  if (message_count <= 0 || messages == nullptr || responses == nullptr) {
    return PAM_CONV_ERR;
  }
  auto* state = static_cast<ConversationState*>(application_data);
  auto* reply = static_cast<pam_response*>(
      std::calloc(static_cast<std::size_t>(message_count), sizeof(pam_response)));
  if (reply == nullptr) {
    return PAM_BUF_ERR;
  }

  for (int index = 0; index < message_count; ++index) {
    const pam_message& message = *messages[index];
    switch (message.msg_style) {
      case PAM_PROMPT_ECHO_OFF:
      case PAM_PROMPT_ECHO_ON: {
        if (state == nullptr || state->terminal == nullptr) {
          std::free(reply);
          return PAM_CONV_ERR;
        }
        std::string value = read_line(state->terminal, message.msg,
                                      message.msg_style == PAM_PROMPT_ECHO_ON);
        reply[index].resp = strdup(value.c_str());
        explicit_bzero(value.data(), value.size());
        if (reply[index].resp == nullptr) {
          for (int previous = 0; previous < index; ++previous) {
            std::free(reply[previous].resp);
          }
          std::free(reply);
          return PAM_BUF_ERR;
        }
        break;
      }
      case PAM_ERROR_MSG:
      case PAM_TEXT_INFO:
        if (state != nullptr && state->terminal != nullptr) {
          std::fprintf(state->terminal, "%s\n", message.msg);
        }
        break;
      default:
        std::free(reply);
        return PAM_CONV_ERR;
    }
  }
  *responses = reply;
  return PAM_SUCCESS;
}

void print_result(const char* operation, int status, pam_handle_t* handle) {
  std::cout << operation << '=' << (status == PAM_SUCCESS ? "pass" : "fail")
            << " pam_status=" << status;
  if (status != PAM_SUCCESS) {
    std::cout << " message=\"" << pam_strerror(handle, status) << '\"';
  }
  std::cout << '\n';
}

}  // namespace

int main(int argc, char** argv) {
  const bool account_only = argc == 3 && std::string(argv[1]) == "--account-only";
  if ((!account_only && argc != 2) || (account_only && argc != 3)) {
    std::cerr << "usage: " << argv[0] << " [--account-only] USER\n";
    return 2;
  }
  const char* user = argv[account_only ? 2 : 1];
  ConversationState state;
  if (!account_only) {
    state.terminal = std::fopen("/dev/tty", "r+");
    if (state.terminal == nullptr) {
      std::cerr << "interactive authentication requires a controlling TTY\n";
      return 3;
    }
  }

  const pam_conv conversation{converse, &state};
  pam_handle_t* handle = nullptr;
  int status = pam_start("stationconnect-host", user, &conversation, &handle);
  print_result("pam_start", status, handle);
  if (status != PAM_SUCCESS) {
    if (state.terminal != nullptr) {
      std::fclose(state.terminal);
    }
    return 4;
  }
  pam_set_item(handle, PAM_RHOST, "local-qualification");
  pam_set_item(handle, PAM_TTY, "stationconnect-probe");

  if (!account_only) {
    status = pam_authenticate(handle, 0);
    print_result("pam_authenticate", status, handle);
  }
  if (status == PAM_SUCCESS) {
    status = pam_acct_mgmt(handle, 0);
    print_result("pam_acct_mgmt", status, handle);
  }
  if (!account_only && status == PAM_SUCCESS) {
    status = pam_setcred(handle, PAM_ESTABLISH_CRED);
    print_result("pam_setcred_establish", status, handle);
  }
  bool session_open = false;
  if (!account_only && status == PAM_SUCCESS) {
    status = pam_open_session(handle, 0);
    print_result("pam_open_session", status, handle);
    session_open = status == PAM_SUCCESS;
  }
  if (session_open) {
    const int close_status = pam_close_session(handle, 0);
    print_result("pam_close_session", close_status, handle);
    if (status == PAM_SUCCESS) {
      status = close_status;
    }
    const int credential_status = pam_setcred(handle, PAM_DELETE_CRED);
    print_result("pam_setcred_delete", credential_status, handle);
    if (status == PAM_SUCCESS) {
      status = credential_status;
    }
  }
  const int end_status = pam_end(handle, status);
  std::cout << "pam_end=" << (end_status == PAM_SUCCESS ? "pass" : "fail")
            << " pam_status=" << end_status << '\n';
  if (state.terminal != nullptr) {
    std::fclose(state.terminal);
  }
  return status == PAM_SUCCESS && end_status == PAM_SUCCESS ? 0 : 5;
}
