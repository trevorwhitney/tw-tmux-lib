#!/bin/bash

df / | tail -n 1 | cut -d ' ' -f 6
