"""Failure controls for the standalone build's dependency and timing admission.
SPDX-License-Identifier: GPL-3.0-only
"""
import importlib.util
from pathlib import Path
import tempfile
import unittest

spec = importlib.util.spec_from_file_location('build', Path(__file__).with_name('build.py'))
build = importlib.util.module_from_spec(spec)
spec.loader.exec_module(build)


class AdmissionTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        (self.root / 'src/fpga/apf').mkdir(parents=True)

    def write(self, name, text):
        path = self.root / name
        path.write_text(text, encoding='utf-8')
        return path

    def test_recursive_qip_missing_source_is_rejected(self):
        self.write('src/fpga/ap_core.qsf', 'set_global_assignment -name QIP_FILE apf/test.qip\n')
        self.write('src/fpga/apf/test.qip', 'set_global_assignment -name VERILOG_FILE [file join $::quartus(qip_path) "missing.v"]\n')
        with self.assertRaisesRegex(RuntimeError, 'Missing dependency'):
            build.project_references(self.root)

    def test_external_dependency_is_rejected(self):
        self.write('src/fpga/ap_core.qsf', 'set_global_assignment -name VERILOG_FILE ../../../external.v\n')
        with self.assertRaisesRegex(RuntimeError, 'External dependency'):
            build.project_references(self.root)

    def test_nested_qip_and_hook_resolve_from_their_directories(self):
        self.write('src/fpga/ap_core.qsf', 'set_global_assignment -name QIP_FILE apf/test.qip\nset_global_assignment -name PRE_FLOW_SCRIPT_FILE "quartus_sh:apf/hook.tcl"\n')
        self.write('src/fpga/apf/test.qip', 'set_global_assignment -entity nested -name VERILOG_FILE [file join $::quartus(qip_path) "module.v"]\n')
        self.write('src/fpga/apf/module.v', 'module test; endmodule\n')
        self.write('src/fpga/apf/hook.tcl', '# hook\n')
        self.assertEqual(len(build.project_references(self.root)), 3)

    def test_unsupported_tcl_dependency_is_not_silently_skipped(self):
        self.write('src/fpga/ap_core.qsf', 'set_global_assignment -name QIP_FILE $external\n')
        with self.assertRaisesRegex(RuntimeError, 'Unsupported dependency'):
            build.project_references(self.root)

    def test_negative_setup_and_nonzero_tns_are_rejected(self):
        for slack, tns in [('-0.001', '0.000'), ('0.100', '-0.001')]:
            with self.subTest(slack=slack, tns=tns):
                report = self.write('timing.rpt', f'; Slow 1100mV 85C Model Setup Summary ;\n; Clock ; Slack ; TNS ;\n; cpu ; {slack} ; {tns} ;\n\n')
                with self.assertRaisesRegex(RuntimeError, 'Timing failure'):
                    build.timing_coverage(report)

    def test_empty_timing_report_is_rejected(self):
        with self.assertRaisesRegex(RuntimeError, 'No timing summary rows'):
            build.timing_coverage(self.write('empty.rpt', 'Compilation finished\n'))


if __name__ == '__main__':
    unittest.main()
