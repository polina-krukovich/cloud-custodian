#!/usr/bin/env python3.6
# -*- coding: utf-8 -*-
"""Ratchet up successes under Python 3.6.
"""
from __future__ import (
    absolute_import, division, print_function, unicode_literals)

import sys
import xml.etree.ElementTree as Etree



class TestResults(object):

    def __init__(self, results_path):
        self.results_path = results_path
        self.failed = []
        self.failed_aggregates = {}
        self.stderr_output = []
        self.passed = []
        self._tree = None

    def parse(self):
        if self._tree:
            raise AssertionError("Already Parsed")
        self._tree = Etree.parse(self.results_path)
        for testcase in self._tree.findall('testcase'):
            self.process_testcase(testcase)
        return self

    def process_testcase(self, case):
        key = self.case_key(case)

        fails = case.findall('failure')
        if not len(case):
            self.passed.append(key)
        elif not fails:
            self.passed.append(key)
            tags = set([i.tag for i in case])
            if tags == set(['system-err']):
                self.stderr_output.append(key)
                return
            raise AssertionError("unknown result for %s" % key)
        else:
            self.failed.append(key)
            self.failed_aggregates.setdefault(
                fails[0].get('message'), []).append(key)

    @staticmethod
    def case_key(case):
        return "%s.%s" % (case.get('classname'), case.get('name'))

    def report(self, details=False):
        for k, v in sorted(
                self.failed_aggregates.items(),
                key = lambda i: len(i[1]),
                reverse=True):
            print("# %s" % k)
            for t in v:
                print(" - %s" % t)


def load_expected_successes(txt):
    expected_successes = open(txt).read()
    parsed = set()
    for line in expected_successes.splitlines():
        if not line or line.startswith('#'):
            continue
        parsed.add(line)
    return parsed


def list_tests(tests):
    for test in sorted(tests):
        print(' ', test)


def add_to_txt(txt_path, tests):
    old = set(open(txt_path, 'r'))
    new = set(t + '\n' for t in tests)
    merged = sorted(old | new)
    open(txt_path, 'w+').writelines(merged)


def main(xml_path, txt_path):
    """Takes two paths, one to XML output from pytest, the other to a text file
    listing expected successes. Walks the former looking for the latter.
    """
    results = TestResults(xml_path).parse()

    if txt_path == 'display':
        results.report()
        return

    previous = load_expected_successes(txt_path)
    expected = previous - set(results.passed)
    if expected:
        print("Some tests required to pass under Python 3.6 didn't:")
        list_tests(expected)

    unexpected = set(results.passed) - previous
    if unexpected:
        print("Some tests not required to pass under Python 3.6 did:")
        list_tests(unexpected)
        add_to_txt(txt_path, unexpected)
        print("Conveniently, they have been added to {} for you. Perhaps "
              "commit that?".format(txt_path))
    if expected or unexpected:
        print(
            "Previously %d passing, now %d" % (
                len(previous), len(results.passed)))
        return 1
    print('All and only tests required to pass under Python 3.6 did.')
    return 0


if __name__ == '__main__':
    try:
        xml_path, txt_path = sys.argv[1:3]
    except ValueError:
        script = sys.argv[0]
        print('usage: {} <junitxml filepath> <expected successes filepath>'
              .format(script), file=sys.stderr)
        result = 1
    else:
        result = main(xml_path, txt_path)
    sys.exit(result)
