{
  inputs.dep.url = "path:@DIR@/dep";
  inputs.raw = { url = "path:@DIR@/raw"; flake = false; };
  outputs = { self, dep, raw }: {
    answer = dep.outputs.value + 1;
    rawText = builtins.readFile (raw + "/data.txt");
    inputNames = builtins.attrNames self.inputs;
    type = self._type;
  };
}
