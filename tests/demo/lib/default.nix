{
  lib,
  inputs,
  namespace,
}:
{
  greet = n: "Hello, ${n} from purr lib!";
  getMeta = { inherit namespace lib inputs; };
}
