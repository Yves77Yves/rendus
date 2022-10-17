// SPDX-License-Identifier: GPL-3.0

/*
 *  5 Ameliorations proposées
 *
 *      Un indice est utilisé pour gérer les différents statuts. (Création de la fonction 'oneStepForward).
 *
 *      Départage des propositions ayant reçu le meme nombre de voix : formule avec Keccak256 et modulo.  (Création de la fonction 'chooseWinner)
 *
 *      Une fois les votes publiés, et après un temps fixé après la publication des votes (ici 60 secondes), le owner peut réinitialiser un nouveau vote(création de la fonction 'reset').
 *
 *      Le decompte des voix entraine le passage automatique à l'état "VotesTallied" et l'enregistrement d'un timestamp. (dans la fonction countVote)
 *      Ce timestamp est utilisé pour gérer le délai d'attente avant de pourvoir réinitiliaser une nouvelle campagne de vote.
 *
 *      Un booleen est mis en place pour ne pas designer de gagnant lorqu'il n'y a eu aucun vote (boolean oneVote)
 *
 */

pragma solidity 0.8.17;

import "https://github.com/OpenZeppelin/openzeppelin-contracts/blob/master/contracts/access/Ownable.sol";

contract Voting is Ownable {
    /*
     * Déclaration des variables
     */

    struct Voter {
        // structure des votants
        bool isRegistered;
        bool hasVoted;
        uint256 votedProposalId;
    }

    struct Proposal {
        // structure des propositions
        string description;
        uint256 voteCount;
    }

    mapping(address => Voter) private whitelist; // liste des voters

    address[] votersAddress; // conservation de la liste des personnes ayant vote. Utilisé pour réinitiliser le vote dans la whitelist.

    Proposal[] proposals; // tableau des propositions

    uint256[] winningProposalIds; // Id[] des propositions arrivées à égalité en première place, utilisé pour le départage

    uint256 proposalId; // Id de la proposition

    uint256 winningProposalId; // Id de la proposition gagnante

    uint256 timestampTallied; // timestamp  utilisé pour donner un délai avant la réinitialisation

    bool oneVote; // booleen pour s'assurer qu'au moins un vote a été émis

    /*
     * declaration des statuts du workflow
     */

    enum WorkflowStatus {
        RegisteringVoters, // enregistrement des votants possible dès la création du contrat par l'admin.
        ProposalsRegistrationStarted, // début de la sessions d'enregistrement des propositions par les whitelistés
        ProposalsRegistrationEnded, // fin de la session d'enregistrement
        VotingSessionStarted, // début de la session de vote des whitelistés
        VotingSessionEnded, // fin de la session de vote. Le décompte avec le choix du winner peut être lancé par l'admin.
        VotesTallied // les votes ont été publiés. Un vote peut être relancé par l'admin passé un délai d'attente de 60 secondes
    }

    WorkflowStatus newStatus = WorkflowStatus.RegisteringVoters; // les voters peuvent être enregistrés par l'administrateur dès la création du contrat
    WorkflowStatus previousStatus; // declaration d'un status precedant
    uint256 workflowIndice = 0; // les voters peuvent être enregistrés par l'administrateur dès la création du contrat

    /*
     ** Déclaration des events.
     */

    event VoterRegistered(address voterAddress); // émis a chaque enregistrement de Votant

    event WorkflowStatusChange(
        // émis à chaque changement de status
        WorkflowStatus previousStatus,
        WorkflowStatus newStatus
    );

    event ProposalRegistered(uint256 proposalId); // émis à chaque enregistreent de proposition
    event Voted(address voter, uint256 proposalId); // émis à chaque vote

    event VoteReInitialized(uint256 timestamp); // emet le vote a été réinitilisé

    modifier onlyWhitelist() {
        // modifier n'autorisant que les whitelistés
        require(
            whitelist[msg.sender].isRegistered,
            "vous n'etes pas autorise a faire cette action"
        );
        _;
    }

    /*
     * La fonction OneStepForward permet au seul owner (modifier onlyOwner) de faire avancer le workflow du vote.
     * Un event est emis à chaque changement de Workflow
     * A noter que le passage à l'état VoteTallied sera automatiquement effectué après le decompte des voix.
     * Il n'y a donc que 4 activations 'by click' pour passer au next Step, le  passage au status voteTallied est lancé par la fonction countVote.
     */

    function OneStepForward() public onlyOwner {
        // seul le owner peut faire avancer le work flow.
        require(
            newStatus != WorkflowStatus.VotingSessionEnded,
            "vous devez lancer le countVote pour passer automatiquement au status VotesTallied "
        );
        require(
            newStatus != WorkflowStatus.VotesTallied,
            "le vote est termine et l'etape finale a deja ete atteinte "
        );
        previousStatus = newStatus;
        newStatus = WorkflowStatus(uint256(newStatus) + 1);
        emit WorkflowStatusChange(previousStatus, newStatus);
    }

    /*
     * La fonction getWorkflowStatus permet a chacun de connaitre l'état du workflow du vote.
     */

    function getWorkflowStatus() public view returns (WorkflowStatus) {
        // tout le monde peut voir le statut du workflow.
        return newStatus;
    }

    /*
     ** L'administrateur du vote enregistre une liste blanche d'électeurs identifiés par leur adresse Ethereum.
     ** Un event est emis pour signifier l'enregistrement des votants.
     */

    function Whitelist(address _address) public onlyOwner {
        require(
            newStatus == WorkflowStatus.RegisteringVoters,
            "la session inscription des votants est cloturee"
        );
        require(_address != address(0));
        require(!whitelist[_address].isRegistered, "deja inscrit");

        whitelist[_address].isRegistered = true; // autorise l'adresse à voter
        votersAddress.push(_address); // conservation des adresses ayant un droit de vote pour la réinitilisations

        emit VoterRegistered(_address); // Triggering event
    }

    /*
     ** Tout le monde peut consulter la liste des whitelistés.
     */

    function getWhitelist(address _address)
        public
        view
        returns (Voter memory)
    {
        return whitelist[_address];
    }

    /*
     ** La fonction 'ProposalRegister' permet aux adresse whitelistées de soumettre une proposition.
     ** Un event est emis pour signifier la soumission d'une nouvelle proposition.
     */

    function ProposalRegister(string calldata _description)
        public
        onlyWhitelist
    {
        require(
            newStatus == WorkflowStatus.ProposalsRegistrationStarted,
            "la session de propositions n'est pas ouverte"
        );

        Proposal memory proposal;

        proposal.description = _description;
        proposals.push(proposal);

        emit ProposalRegistered(proposals.length - 1); // Triggering event
    }

    /*
     * La fonction 'getProposal' permet aux adresses whitelistées de connaitre les propositions emises.
     */

    function getProposal(uint256 _Id)
        public
        view
        onlyWhitelist
        returns (Proposal memory)
    {
        require(_Id < proposals.length, "cette proposition n'existe pas");
        return proposals[_Id];
    }

    /*
     * La fonction 'Vote' permet aux adresse whitelistées de choisir une proposition parmi celles qui ont été proposées.
     * Un event est emis pour signifier l'émission d'un vote.
     */

    function Vote(uint256 _proposalId) public onlyWhitelist {
        require(
            newStatus == WorkflowStatus.VotingSessionStarted,
            "la session de votes n'est pas ouverte"
        );
        require(
            _proposalId < proposals.length,
            "cette proposition n'existe pas"
        );
        require(!whitelist[msg.sender].hasVoted, "vous avez deja vote");

        proposals[_proposalId].voteCount++; // comptabilise un vote pour la proposition choisie
        whitelist[msg.sender].hasVoted = true; // enregistre le voter
        whitelist[msg.sender].votedProposalId = _proposalId; // enregistre la proposition choisie par le voter
        oneVote = true; // enregistre qu'au moins un vote a été émis : utile pour shunter la désignation du winner si aucun vote n'a été émis

        emit VoterRegistered(msg.sender); // Triggering event
    }

    /*
     * La fonction 'getVote' permet à une personne whitelistée de consulter le vote d'une autre personne.
     * le vote d'un electeur est consultable des que l'electeur a emis son vote (comme dans un vote a main levee).
     */

    function getVote(address _address)
        public
        view
        onlyWhitelist
        returns (uint256)
    {
        require(
            whitelist[_address].hasVoted == true,
            "cette personne na pas vote"
        );

        return whitelist[_address].votedProposalId;
    }

    /*
     * La fonction 'countVote' permet de connaitre la proposition gagnante.
     * Elle realise le decompte des voix et retient le/les propositions qui ont le plus de voix.
     * Une fois ce decompte effectué,elle appelle 'chooseWinner' qui désigne e gagnant désigné,  le workflow passe automatique au status 'voteTallied' et
     * et le timestamp est enregistré pour gérer le délai avant la réinitialisation.
     */

    function countVote() public onlyOwner {
        require(
            newStatus == WorkflowStatus.VotingSessionEnded,
            "le vote doit etre cloture pour lancer le comptage des voix"
        );
        

        uint256 countVoteMax = 0;

        for (uint256 i = 0; i < proposals.length; i++) {
            // met en array le/les propostions avec le max de voix
            if (proposals[i].voteCount == countVoteMax) {
                winningProposalIds.push(i);
            } else {
                if (proposals[i].voteCount > countVoteMax) {
                    delete winningProposalIds;
                    countVoteMax = proposals[i].voteCount;
                    winningProposalIds.push(i);
                }
            }
        }

        if (oneVote == true) {
            chooseWinner(); // selectionne un winner si il y a eu au moins un vote
        }

        newStatus = WorkflowStatus.VotesTallied; // passer en statut VotesTallied après le comptage des votes
        timestampTallied = block.timestamp; // utilisé pour la réinitialisation qui ne pourra se faire que  60 secondes après le décompte des voix.
    }

    /*
     * La fonction getWinner permet à chacun, whiteliste ou non, de connaitre la proposition qui a emporté le vote
     * Elle n'est accessible qu'après le decompte des voix effectué et le gagnnant designé (mode VotesTallied)
     * Si il n'y a eu aucun vote, le winner n'est pas désigné
     */

    function getWinner() public view returns (uint256) {
        require(
            newStatus == WorkflowStatus.VotesTallied,
            "Voting must be tallied before publishing"
        );
        require(
            oneVote == true,
            "Aucun vote emis : il ny a pas de gagnant"
        );
        return winningProposalId;
    }

    /*
     * Le fonction 'reset' permet de réinitiliser les listes et de relancer un nouveau vote.
     * La fonction garde les adresses de la whitelist mais re-initialise tous les statuts et compteurs.
     * La liste des propositions est supprimée.
     * Un nouveau vote est ouvert en status 'RegisteringVoters' et le owner peut alors ressaisir de nouveaux votants pour un nouveau vote.
     * Un event avec le timestamp est emis pour indiquer la réinitalisation.
     */

    function reset() public onlyOwner {
        require(
            newStatus == WorkflowStatus.VotesTallied,
            "un vote en cours ne peut pas etre reinitialise"
        );
        require(
            block.timestamp > timestampTallied + 60,
            "il est trop tot pour re-initialiser le vote. Attendre 60 secondes apres le comptage des voix"
        );

        for (uint256 i; i < votersAddress.length; i++) {
            // initilisation de la whitelist
            whitelist[votersAddress[i]].isRegistered = false;
            whitelist[votersAddress[i]].hasVoted = false;
            whitelist[votersAddress[i]].votedProposalId = 0;
        }

        delete proposals; // suppression des propositions
        delete winningProposalIds; // suppression des propositions ex-aequo
        delete votersAddress; // suppression des personnes ayant voté

        winningProposalId = 0; // initialise le winingProposalId
        newStatus = WorkflowStatus.RegisteringVoters; // initialise le status au début du workflow

        oneVote = false; // initialise le booleen d'existence d'un vote

        emit VoteReInitialized(block.timestamp); // Triggering event
    }

    /*
     * La fonction interne chooseWinner permet designer le  gagnant
     * Départage des gagnants :
     *    le keccak fournit  le hash du timestamp de la transaction puis est transformé en uint par le prefixe uint.
     *    le modulo de ce uint(keccak) par la longueur de la table des gagnants retourne un reste compris entre 0 et length-1.
     *    Ce reste sera considéré comme l'Id gagnant.
     *
     *    le contrôle if length == 1 n'est pas nécessaire.  La formule de calcul du winner fonctionne pour length = 1.
     *    Ce 'if' a toutefois été ajouté pour ne pas calculer de keccak inutilement quand il n'y a qu'un winner. (économie de Gas)
     */

    function chooseWinner() internal {
        if (winningProposalIds.length == 1) {
            // evite le calcul d'un keccak en cas de gagnant unique
            winningProposalId = winningProposalIds[0];
        } else {
            // departage des ex-aequo
            winningProposalId = winningProposalIds[
                uint256(keccak256(abi.encodePacked(block.timestamp))) %
                    winningProposalIds.length
            ];
        }
    }
}
