# Fonctions en PL/pgSQL pour changer un classement

Les fonctions présentées ici correspondent aux différents codes sources présentés
dans la série d’articles publiées à ces adresses :

 - <https://cogito-ergo-dev.fr/blog/54996/trier-avec-postgresql-partie-1/>
 - <https://cogito-ergo-dev.fr/blog/55188/trier-avec-postgresql-partie-2/>

## part_one.sql

Ce fichier définit des fonctions pour trier des données dans une table ne dépendant pas
de regroupement.

## part_two.sql

Ce fichier permet la même chose que le précédent, mais avec des fonctions dans
une version spécialisée pour gérer des données d’une table dépendant d’un système de regroupement.
