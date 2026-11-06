// The C++ side of scripts/bench_codec.py: see bench.goose, which this matches. A message
// and an output string are reused between rounds, as a program that cares would.
#include <algorithm>
#include <chrono>
#include <cstdio>
#include <cstdlib>
#include <fstream>
#include <iostream>
#include <iterator>
#include <string>

#include "codec.pb.h"

using Clock = std::chrono::steady_clock;

static double since(Clock::time_point start) {
  return std::chrono::duration<double>(Clock::now() - start).count();
}

template <typename T>
static void run(const char* name, const std::string& input, double seconds, int rounds) {
  T m;
  double best_decode = 1e30;
  for (int round = 0; round < rounds; round++) {
    long n = 0;
    auto start = Clock::now();
    while (since(start) < seconds) {
      if (!m.ParseFromArray(input.data(), static_cast<int>(input.size()))) std::abort();
      m.Clear();
      n++;
    }
    best_decode = std::min(best_decode, since(start) / n);
  }
  if (!m.ParseFromArray(input.data(), static_cast<int>(input.size()))) std::abort();
  std::string out;
  double best_encode = 1e30;
  for (int round = 0; round < rounds; round++) {
    long n = 0;
    auto start = Clock::now();
    while (since(start) < seconds) {
      out.clear();
      if (!m.SerializeToString(&out)) std::abort();
      n++;
    }
    best_encode = std::min(best_encode, since(start) / n);
  }
  std::printf("%s %zu %zu %lld %lld\n", name, input.size(), out.size(),
              static_cast<long long>(best_decode * 1e9), static_cast<long long>(best_encode * 1e9));
}

int main(int argc, char** argv) {
  if (argc != 5) return 2;
  std::string name = argv[1];
  std::ifstream file(argv[2], std::ios::binary);
  std::string input((std::istreambuf_iterator<char>(file)), std::istreambuf_iterator<char>());
  double seconds = std::atof(argv[3]);
  int rounds = std::atoi(argv[4]);
  if (name == "Small") run<codec::Small>(argv[1], input, seconds, rounds);
  else if (name == "Record") run<codec::Record>(argv[1], input, seconds, rounds);
  else if (name == "Batch") run<codec::Batch>(argv[1], input, seconds, rounds);
  else if (name == "Ints") run<codec::Ints>(argv[1], input, seconds, rounds);
  else if (name == "Strings") run<codec::Strings>(argv[1], input, seconds, rounds);
  else if (name == "Blob") run<codec::Blob>(argv[1], input, seconds, rounds);
  else if (name == "Table") run<codec::Table>(argv[1], input, seconds, rounds);
  else return 2;
  return 0;
}
