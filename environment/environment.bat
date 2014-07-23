@echo off

IF [%1] == [-n] (
    uperl environment.pl 0
) ELSE IF [%1] == [-u] (
    uperl environment.pl 1
) ELSE (
    echo use switch -n for a new environment or -u for update an old one
)