pragma solidity =0.6.6;

library QuickSort {
    function sort(address[] memory array, uint256[] memory orderArray) internal pure {
        _sort(array, orderArray, 0, int256(array.length - 1));
    }

    function _sort(
        address[] memory array,
        uint256[] memory orderArray,
        int256 left,
        int256 right
    ) private pure {
        if (left == right) {
            return;
        }

        int256 l = left;
        int256 r = right;
        address pivot = array[uint256((l + r) / 2)];

        while (l <= r) {
            while (array[uint256(l)] < pivot) {
                l++;
            }

            while (pivot < array[uint256(r)]) {
                r--;
            }

            if (l <= r) {
                (array[uint256(l)], array[uint256(r)]) = (array[uint256(r)], array[uint256(l)]);
                (orderArray[uint256(l)], orderArray[uint256(r)]) = (orderArray[uint256(r)], orderArray[uint256(l)]);
                l++;
                r--;
            }
        }

        if (left < r) {
            _sort(array, orderArray, left, r);
        }

        if (l < right) {
            _sort(array, orderArray, l, right);
        }
    }
}
