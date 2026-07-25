{ stdenv, lib, ... }: {
  foundStdenv = stdenv == "mock-stdenv";
  libWorks = lib == "custom-lib";
}
