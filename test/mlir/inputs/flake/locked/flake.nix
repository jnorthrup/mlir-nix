{ inputs.dep.url = "x"; inputs.inner.url = "y"; outputs = { self, dep, inner }: { viaInner = inner.outputs.seen; }; }
