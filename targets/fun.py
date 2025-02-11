def add_numbers(a: int, b: int) -> int:
    return a + b

def is_palindrome(s: str) -> bool:
    s = ''.join(c.lower() for c in s if c.isalnum())
    return s == s[::-1]

def fibonacci(n: int) -> int:
    if n <= 0:
        raise ValueError("n must be a positive integer.")
    if n == 1:
        return 0
    if n == 2:
        return 1
    a, b = 0, 1
    for _ in range(n - 2):
        a, b = b, a + b
    return b

def find_anagrams(word: str, words: list) -> list:
    sorted_word = ''.join(sorted(word))
    return [w for w in words if ''.join(sorted(w)) == sorted_word]

import heapq

def shortest_path(graph: dict, start: str, end: str) -> int:
    if start not in graph or end not in graph:
        raise ValueError("Start or end node not in graph.")
    pq = [(0, start)]  # (cost, node)
    visited = set()
    costs = {node: float('inf') for node in graph}
    costs[start] = 0

    while pq:
        current_cost, current_node = heapq.heappop(pq)
        if current_node in visited:
            continue
        visited.add(current_node)
        if current_node == end:
            return current_cost
        for neighbor, weight in graph[current_node]:
            new_cost = current_cost + weight
            if new_cost < costs[neighbor]:
                costs[neighbor] = new_cost
                heapq.heappush(pq, (new_cost, neighbor))
    
    return costs[end] if costs[end] != float('inf') else -1

import operator
import re

def parse_and_evaluate_expression(expr: str) -> float:
    ops = {
        '+': operator.add,
        '-': operator.sub,
        '*': operator.mul,
        '/': operator.truediv,
    }

    def eval_tokens(tokens):
        stack = []
        for token in tokens:
            if token in ops:
                b = stack.pop()
                a = stack.pop()
                stack.append(ops[token](a, b))
            else:
                stack.append(float(token))
        return stack[0]

    def infix_to_postfix(expr):
        precedence = {'+': 1, '-': 1, '*': 2, '/': 2}
        output = []
        operators = []
        tokens = re.findall(r'\d+|\+|\-|\*|\/|\(|\)', expr)
        for token in tokens:
            if token.isdigit():
                output.append(token)
            elif token == '(':
                operators.append(token)
            elif token == ')':
                while operators and operators[-1] != '(':
                    output.append(operators.pop())
                operators.pop()
            else:
                while operators and precedence.get(operators[-1], 0) >= precedence[token]:
                    output.append(operators.pop())
                operators.append(token)
        while operators:
            output.append(operators.pop())
        return output

    postfix_expr = infix_to_postfix(expr)
    return eval_tokens(postfix_expr)

