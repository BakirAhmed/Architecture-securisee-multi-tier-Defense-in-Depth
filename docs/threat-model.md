# Modèle de menaces — Architecture 3 tiers

| Menace | Mesure de mitigation |
|---|---|
| Interception du trafic web | TLS obligatoire sur l'ALB, WAF en amont |
| Attaque applicative (SQLi, XSS) | AWS WAF avec managed rule group OWASP Top 10 |
| Compromission des identifiants base de données | Secrets Manager + rotation automatique 30 jours |
| Exfiltration de données au repos | Chiffrement KMS (CMK) sur RDS, S3, EBS |
| Mouvement latéral entre tiers | Security Groups en cascade (web → app → data uniquement) |
| Activité anormale / reconnaissance | GuardDuty (analyse VPC Flow Logs, DNS, CloudTrail) |
| Dérive de configuration (ressource non chiffrée, port ouvert) | AWS Config Rules + remédiation automatique |
| Absence de visibilité de conformité | Security Hub agrégeant CIS AWS Foundations + PCI DSS |
| Privilèges excessifs | IAM least-privilege, policy explicite refusant les objets S3 non chiffrés |

## Références
- AWS Well-Architected Framework — Security Pillar
- CIS AWS Foundations Benchmark v1.4
- PCI DSS v3.2.1
