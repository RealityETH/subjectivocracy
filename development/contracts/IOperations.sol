// SPDX-License-Identifier: MIT OR Apache-2.0

pragma solidity ^0.8.10;

library Operations {

    enum OpTree {
        Full,
        Rollup
    }

    enum QueueType {
        Deque,
        HeapBuffer,
        Heap
    }

}
