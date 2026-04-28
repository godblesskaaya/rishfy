# Rishfy Team Commit Guide

After team members add their public SSH keys to GitHub, use these commands to commit attributed to each person.

## SSH Agent Status
All 4 team keys are loaded in SSH agent:
- CodeWithStella (SHA256:eGHoof2ekcfITO3z12bFls5JqKOEcBokJg3hHZdXNas)
- Ezzy141 (SHA256:Aov5MLnesn4sfk6iUyKWfLaRp7DN3kDJ+5Ldw4RXAmI)
- fatma-nassib (SHA256:oGZ5KoYJ3G+YQ4kkEsC6UXwF/Hv6mYoXDbVO3BR78Qg)
- godblesskaaya (SHA256:6pOecQStrIMtsWTkYtDGZp+Nvg6AMTesJgxxz4527XE)

## Commit as CodeWithStella

```bash
git config user.name "CodeWithStella"
git config user.email "stellakahungo24@gmail.com"
git commit -m "Your message"
git push
```

## Commit as Ezzy141

```bash
git config user.name "Ezzy141"
git config user.email "mazwaezekiel@gmail.com"
git commit -m "Your message"
git push
```

## Commit as fatma-nassib

```bash
git config user.name "fatma-nassib"
git config user.email "abdallah.nassib.fatma@gmail.com"
git commit -m "Your message"
git push
```

## Commit as godblesskaaya

```bash
git config user.name "godblesskaaya"
git config user.email "godblessgkaaya@gmail.com"
git commit -m "Your message"
git push
```

## Shell Function (Optional)

Add this to your `~/.bashrc` or `~/.zshrc`:

```bash
rishfy_as() {
  local user="$1"
  case "$user" in
    stella)
      git config user.name "CodeWithStella"
      git config user.email "stellakahungo24@gmail.com"
      ;;
    ezzy)
      git config user.name "Ezzy141"
      git config user.email "mazwaezekiel@gmail.com"
      ;;
    fatma)
      git config user.name "fatma-nassib"
      git config user.email "abdallah.nassib.fatma@gmail.com"
      ;;
    godbless)
      git config user.name "godblesskaaya"
      git config user.email "godblessgkaaya@gmail.com"
      ;;
    *)
      echo "Unknown user: $user"
      return 1
      ;;
  esac
  echo "✓ Git configured as $user"
}
```

Then use: `rishfy_as stella && git commit -m "message" && git push`
