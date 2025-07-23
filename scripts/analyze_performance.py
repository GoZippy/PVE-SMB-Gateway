#!/usr/bin/env python3

"""
Performance Analysis Script for PVE SMB Gateway
Analyzes test results and detects performance regressions
"""

import json
import sys
import argparse
from datetime import datetime
from typing import Dict, List, Any
import statistics

class PerformanceAnalyzer:
    def __init__(self, baseline_file: str = None):
        self.baseline_file = baseline_file
        self.baseline_data = self._load_baseline()
        
    def _load_baseline(self) -> Dict[str, Any]:
        """Load baseline performance data if available"""
        if not self.baseline_file:
            return {}
        
        try:
            with open(self.baseline_file, 'r') as f:
                return json.load(f)
        except FileNotFoundError:
            print(f"Warning: Baseline file {self.baseline_file} not found")
            return {}
        except json.JSONDecodeError:
            print(f"Error: Invalid JSON in baseline file {self.baseline_file}")
            return {}
    
    def analyze_results(self, results_file: str) -> Dict[str, Any]:
        """Analyze performance test results"""
        try:
            with open(results_file, 'r') as f:
                results = json.load(f)
        except FileNotFoundError:
            print(f"Error: Results file {results_file} not found")
            return {}
        except json.JSONDecodeError:
            print(f"Error: Invalid JSON in results file {results_file}")
            return {}
        
        analysis = {
            'timestamp': datetime.now().isoformat(),
            'summary': {},
            'regressions': [],
            'improvements': [],
            'recommendations': []
        }
        
        # Analyze each test category
        for test_type, data in results.items():
            if isinstance(data, dict) and 'performance' in data:
                perf_data = data['performance']
                analysis['summary'][test_type] = self._analyze_performance_data(perf_data)
                
                # Check for regressions against baseline
                if self.baseline_data and test_type in self.baseline_data:
                    regression = self._check_regression(
                        test_type, 
                        perf_data, 
                        self.baseline_data[test_type]
                    )
                    if regression:
                        analysis['regressions'].append(regression)
        
        return analysis
    
    def _analyze_performance_data(self, perf_data: Dict[str, Any]) -> Dict[str, Any]:
        """Analyze performance data for a specific test"""
        analysis = {
            'iops': {},
            'throughput': {},
            'latency': {},
            'overall_score': 0
        }
        
        # Analyze IOPS
        if 'iops' in perf_data:
            iops_values = perf_data['iops']
            if isinstance(iops_values, list):
                analysis['iops'] = {
                    'mean': statistics.mean(iops_values),
                    'median': statistics.median(iops_values),
                    'min': min(iops_values),
                    'max': max(iops_values),
                    'std_dev': statistics.stdev(iops_values) if len(iops_values) > 1 else 0
                }
        
        # Analyze throughput
        if 'throughput_mbps' in perf_data:
            throughput_values = perf_data['throughput_mbps']
            if isinstance(throughput_values, list):
                analysis['throughput'] = {
                    'mean': statistics.mean(throughput_values),
                    'median': statistics.median(throughput_values),
                    'min': min(throughput_values),
                    'max': max(throughput_values),
                    'std_dev': statistics.stdev(throughput_values) if len(throughput_values) > 1 else 0
                }
        
        # Analyze latency
        if 'latency_ms' in perf_data:
            latency_values = perf_data['latency_ms']
            if isinstance(latency_values, list):
                analysis['latency'] = {
                    'mean': statistics.mean(latency_values),
                    'median': statistics.median(latency_values),
                    'min': min(latency_values),
                    'max': max(latency_values),
                    'std_dev': statistics.stdev(latency_values) if len(latency_values) > 1 else 0
                }
        
        # Calculate overall score (weighted average)
        scores = []
        weights = []
        
        if analysis['iops']:
            scores.append(analysis['iops']['mean'])
            weights.append(0.4)  # IOPS is 40% of score
        
        if analysis['throughput']:
            scores.append(analysis['throughput']['mean'])
            weights.append(0.4)  # Throughput is 40% of score
        
        if analysis['latency']:
            # Lower latency is better, so invert
            latency_score = 1000 / max(analysis['latency']['mean'], 1)
            scores.append(latency_score)
            weights.append(0.2)  # Latency is 20% of score
        
        if scores and weights:
            total_weight = sum(weights)
            analysis['overall_score'] = sum(s * w for s, w in zip(scores, weights)) / total_weight
        
        return analysis
    
    def _check_regression(self, test_type: str, current: Dict[str, Any], baseline: Dict[str, Any]) -> Dict[str, Any]:
        """Check for performance regressions against baseline"""
        regression = {
            'test_type': test_type,
            'metrics': [],
            'severity': 'low'
        }
        
        # Check IOPS regression
        if 'iops' in current and 'iops' in baseline:
            current_iops = current['iops'].get('mean', 0) if isinstance(current['iops'], dict) else current['iops']
            baseline_iops = baseline['iops'].get('mean', 0) if isinstance(baseline['iops'], dict) else baseline['iops']
            
            if baseline_iops > 0:
                iops_change = (current_iops - baseline_iops) / baseline_iops * 100
                if iops_change < -10:  # More than 10% regression
                    regression['metrics'].append({
                        'metric': 'iops',
                        'current': current_iops,
                        'baseline': baseline_iops,
                        'change_percent': iops_change
                    })
        
        # Check throughput regression
        if 'throughput_mbps' in current and 'throughput_mbps' in baseline:
            current_tp = current['throughput_mbps'].get('mean', 0) if isinstance(current['throughput_mbps'], dict) else current['throughput_mbps']
            baseline_tp = baseline['throughput_mbps'].get('mean', 0) if isinstance(baseline['throughput_mbps'], dict) else baseline['throughput_mbps']
            
            if baseline_tp > 0:
                tp_change = (current_tp - baseline_tp) / baseline_tp * 100
                if tp_change < -10:  # More than 10% regression
                    regression['metrics'].append({
                        'metric': 'throughput',
                        'current': current_tp,
                        'baseline': baseline_tp,
                        'change_percent': tp_change
                    })
        
        # Check latency regression
        if 'latency_ms' in current and 'latency_ms' in baseline:
            current_lat = current['latency_ms'].get('mean', 0) if isinstance(current['latency_ms'], dict) else current['latency_ms']
            baseline_lat = baseline['latency_ms'].get('mean', 0) if isinstance(baseline['latency_ms'], dict) else baseline['latency_ms']
            
            if baseline_lat > 0:
                lat_change = (current_lat - baseline_lat) / baseline_lat * 100
                if lat_change > 20:  # More than 20% increase in latency
                    regression['metrics'].append({
                        'metric': 'latency',
                        'current': current_lat,
                        'baseline': baseline_lat,
                        'change_percent': lat_change
                    })
        
        # Determine severity
        if regression['metrics']:
            max_change = max(abs(m['change_percent']) for m in regression['metrics'])
            if max_change > 50:
                regression['severity'] = 'high'
            elif max_change > 25:
                regression['severity'] = 'medium'
            else:
                regression['severity'] = 'low'
        
        return regression if regression['metrics'] else None
    
    def generate_report(self, analysis: Dict[str, Any], output_file: str = None):
        """Generate a human-readable performance report"""
        report = []
        report.append("=" * 60)
        report.append("PVE SMB Gateway Performance Analysis Report")
        report.append("=" * 60)
        report.append(f"Generated: {analysis.get('timestamp', 'Unknown')}")
        report.append("")
        
        # Summary
        report.append("PERFORMANCE SUMMARY")
        report.append("-" * 20)
        for test_type, summary in analysis.get('summary', {}).items():
            report.append(f"\n{test_type.upper()}:")
            if 'overall_score' in summary:
                report.append(f"  Overall Score: {summary['overall_score']:.2f}")
            
            if 'iops' in summary:
                iops = summary['iops']
                report.append(f"  IOPS: {iops['mean']:.2f} ± {iops['std_dev']:.2f}")
            
            if 'throughput' in summary:
                tp = summary['throughput']
                report.append(f"  Throughput: {tp['mean']:.2f} MB/s ± {tp['std_dev']:.2f}")
            
            if 'latency' in summary:
                lat = summary['latency']
                report.append(f"  Latency: {lat['mean']:.2f} ms ± {lat['std_dev']:.2f}")
        
        # Regressions
        if analysis.get('regressions'):
            report.append("\n" + "=" * 60)
            report.append("PERFORMANCE REGRESSIONS DETECTED")
            report.append("=" * 60)
            
            for regression in analysis['regressions']:
                severity_color = {
                    'high': '🔴',
                    'medium': '🟡', 
                    'low': '🟢'
                }.get(regression['severity'], '⚪')
                
                report.append(f"\n{severity_color} {regression['test_type'].upper()} ({regression['severity'].upper()})")
                
                for metric in regression['metrics']:
                    report.append(f"  {metric['metric'].upper()}: {metric['change_percent']:+.1f}%")
                    report.append(f"    Current: {metric['current']:.2f}")
                    report.append(f"    Baseline: {metric['baseline']:.2f}")
        else:
            report.append("\n✅ No performance regressions detected")
        
        # Recommendations
        if analysis.get('regressions'):
            report.append("\n" + "=" * 60)
            report.append("RECOMMENDATIONS")
            report.append("=" * 60)
            
            high_severity = [r for r in analysis['regressions'] if r['severity'] == 'high']
            if high_severity:
                report.append("🔴 HIGH PRIORITY:")
                report.append("  - Investigate performance regressions immediately")
                report.append("  - Review recent code changes")
                report.append("  - Check system resource utilization")
            
            medium_severity = [r for r in analysis['regressions'] if r['severity'] == 'medium']
            if medium_severity:
                report.append("\n🟡 MEDIUM PRIORITY:")
                report.append("  - Monitor performance trends")
                report.append("  - Consider optimization opportunities")
        
        report_text = "\n".join(report)
        
        if output_file:
            with open(output_file, 'w') as f:
                f.write(report_text)
            print(f"Report written to: {output_file}")
        else:
            print(report_text)
        
        return report_text

def main():
    parser = argparse.ArgumentParser(description='Analyze PVE SMB Gateway performance test results')
    parser.add_argument('results_file', help='Path to performance results JSON file')
    parser.add_argument('--baseline', help='Path to baseline performance data')
    parser.add_argument('--output', help='Output file for the report')
    parser.add_argument('--json', action='store_true', help='Output analysis as JSON')
    
    args = parser.parse_args()
    
    analyzer = PerformanceAnalyzer(args.baseline)
    analysis = analyzer.analyze_results(args.results_file)
    
    if args.json:
        print(json.dumps(analysis, indent=2))
    else:
        analyzer.generate_report(analysis, args.output)
    
    # Exit with error code if high severity regressions found
    high_severity_regressions = [r for r in analysis.get('regressions', []) if r['severity'] == 'high']
    if high_severity_regressions:
        sys.exit(1)

if __name__ == '__main__':
    main() 