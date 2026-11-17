{ inputs.dep.url = "path:/nonexistent"; outputs = { self, dep }: { seen = dep.outputs.name; }; }
