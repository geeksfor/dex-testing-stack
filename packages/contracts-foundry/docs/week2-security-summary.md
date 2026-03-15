# Week2 Security Regression Summary

## What I built
- Reentrancy: Vuln vs Fixed + exploit regression
- Rounding dust: 0-share mint donation + fixed revert
- Approve race: front-run allowance double spend + mitigation pattern
- Slither report: top findings and triage

## Key takeaways (interview-ready)
1) Reentrancy = external call before state update; fix with CEI + nonReentrant  
2) Rounding dust = floor rounding creates donation; fix by revert dust deposit / virtual shares  
3) Approve race = allowance update is not atomic; fix with permit / inc/dec allowance / set 0 first

## Next
- Add invariant: totalAssets/share accounting properties
- Add fuzz: attacker behaviors + constrained inputs