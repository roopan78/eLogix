/** A GPS provider that can report the current position of every vehicle on an Active trip (Phase 6). */
public interface IGpsProvider {
    List<GpsPing> currentPositions();
}
