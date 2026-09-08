#include "streaming/frameflowbuffer.h"
#include <cassert>
#include <thread>
#include <iostream>

int main() {
    FrameFlowBuffer disabled(false);
    disabled.record({1, 2, 3, 1, 1, 4, 0, 0});
    assert(disabled.take().empty());
    FrameFlowBuffer bounded(true);
    bounded.record({10, 2, 3, 1, 1, 4, 0, 0});
    bounded.record({9, 2, 3, 1, 1, 4, 0, 0}); // earlier racing producer
    bounded.record({10 + FrameFlowBuffer::WindowNs, 2, 3, 1, 1, 4, 0, 0});
    assert(bounded.take().size() == 1);
    for (size_t i = 0; i < FrameFlowBuffer::Capacity + 10; ++i)
        bounded.record({100 + i, 2, 3, 1, 1, 4, 0, 0});
    assert(bounded.take().size() == FrameFlowBuffer::Capacity);
    assert(bounded.take().empty());
    auto produce = [&] { for (int i = 0; i < 2000; ++i)
        bounded.record({200, 2, 3, 7, 1, 4, 3, 100}); };
    std::thread a(produce), b(produce);
    a.join(); b.join();
    const auto rows = bounded.take();
    assert(rows.size() == 4000 && rows[0].depth == 3 && rows[0].stage == 7);
    std::cout << "client_frame_flow_pass=1 disabled=1 bounded=1 window=1 reset=1 concurrent=1\n";
}
